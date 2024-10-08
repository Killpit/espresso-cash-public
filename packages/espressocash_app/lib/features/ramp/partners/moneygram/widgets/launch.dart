import 'package:decimal/decimal.dart';
import 'package:dfunc/dfunc.dart';
import 'package:espressocash_api/espressocash_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../../../../di.dart';
import '../../../../../l10n/device_locale.dart';
import '../../../../../l10n/l10n.dart';
import '../../../../../ui/dialogs.dart';
import '../../../../../ui/loader.dart';
import '../../../../../ui/snackbar.dart';
import '../../../../../ui/theme.dart';
import '../../../../../ui/web_view_screen.dart';
import '../../../../../utils/errors.dart';
import '../../../../conversion_rates/services/amount_ext.dart';
import '../../../../conversion_rates/widgets/extensions.dart';
import '../../../../currency/models/amount.dart';
import '../../../../currency/models/currency.dart';
import '../../../../ramp_partner/models/ramp_partner.dart';
import '../../../../stellar/models/stellar_wallet.dart';
import '../../../../stellar/service/stellar_client.dart';
import '../../../../tokens/token.dart';
import '../../../models/profile_data.dart';
import '../../../models/ramp_type.dart';
import '../../../screens/off_ramp_order_screen.dart';
import '../../../screens/on_ramp_order_screen.dart';
import '../../../screens/ramp_amount_screen.dart';
import '../data/dto.dart';
import '../data/moneygram_client.dart';
import '../service/moneygram_off_ramp_service.dart';
import '../service/moneygram_on_ramp_service.dart';
import 'style.dart';

typedef MoneygramLink = ({String id, String url, String token});

extension BuildContextExt on BuildContext {
  Future<void> launchMoneygramOnRamp({
    required ProfileData profile,
  }) async {
    FiatAmount? amount;

    const partner = RampPartner.moneygram;
    const type = RampType.onRamp;

    await RampAmountScreen.push(
      this,
      partner: partner,
      onSubmitted: (Amount? value) {
        Navigator.pop(this);
        amount = value as FiatAmount?;
      },
      minAmount: partner.minimumAmountInDecimal,
      currency: Currency.usd,
      receiveCurrency: Currency.usdc,
      type: type,
      calculateEquivalent: (amount) => _calculateReceiveAmount(
        amount: amount,
        type: type,
      ),
      calculateFee: (amount) => _calculateFees(
        amount: amount,
        type: type,
      ),
      exchangeRate: '1 USDC = 1 USDC',
    );

    final submittedAmount = amount;

    if (submittedAmount == null) return;

    final usdcAmount =
        submittedAmount.toTokenAmount(Token.usdc)?.round(Currency.usd.decimals);

    if (usdcAmount == null) {
      showCpErrorSnackbar(this, message: l10n.tryAgainLater);

      return;
    }

    final receiveAmount = await runWithLoader<Amount>(
      this,
      () async => _fetchFees(amount: usdcAmount, type: type)
          .letAsync((p) => p.receiveAmount),
    ) as CryptoAmount;

    final response = await _generateDepositLink(
      amount: usdcAmount.decimal.toDouble(),
    );

    if (response == null) {
      showCpErrorSnackbar(this, message: l10n.tryAgainLater);

      return;
    }

    final link = response.url;
    final token = response.token;
    final orderId = response.id;

    final id = await sl<MoneygramOnRampOrderService>()
        .createPendingMoneygram(
      orderId: orderId,
      submittedAmount: submittedAmount,
      authToken: token,
      receiveAmount: receiveAmount,
      countryCode: profile.country.code,
      bridgeAmount: usdcAmount,
    )
        .then((order) {
      switch (order) {
        case Left<Exception, String>():
          return null;
        case Right<Exception, String>(:final value):
          return value;
      }
    });

    if (id == null) {
      showCpErrorSnackbar(this, message: l10n.tryAgainLater);

      return;
    }

    bool orderWasCreated = false;
    Future<void> handleLoaded(InAppWebViewController controller) async {
      await controller.evaluateJavascript(source: await loadMoneygramStyle());

      controller.addJavaScriptHandler(
        handlerName: 'moneygram',
        callback: (args) async {
          if (orderWasCreated) return;
          orderWasCreated = true;

          OnRampOrderScreen.pushReplacement(this, id: id);
          await sl<MoneygramOnRampOrderService>().updateMoneygramOrder(id: id);
        },
      );
      await controller.evaluateJavascript(
        source: '''
window.addEventListener("message", (event) => {
  window.flutter_inappwebview.callHandler('moneygram', event.data);
}, false);
''',
      );
    }

    await WebViewScreen.push(
      this,
      url: Uri.parse(link),
      onLoaded: handleLoaded,
      title: l10n.ramp_titleCashIn,
      theme: const CpThemeData.light(),
    );

    if (!orderWasCreated) {
      await sl<MoneygramOnRampOrderService>().updateMoneygramOrder(id: id);
    }
  }

  Future<void> launchMoneygramOffRamp({
    required ProfileData profile,
  }) async {
    Amount? amount;

    const partner = RampPartner.moneygram;
    const type = RampType.offRamp;

    await RampAmountScreen.push(
      this,
      partner: partner,
      onSubmitted: (Amount? value) async {
        await showConfirmationDialog(
          this,
          title: 'Confirm Withdrawal',
          message:
              'We will be transferring the amount now. If you cancel after, you will be charged a fee. Are you sure you want to proceed?',
          onConfirm: () {
            Navigator.pop(this);
            amount = value;
          },
        );
      },
      minAmount: partner.minimumAmountInDecimal,
      currency: Currency.usdc,
      receiveCurrency: Currency.usd,
      type: type,
      calculateEquivalent: (amount) => _calculateReceiveAmount(
        amount: amount,
        type: type,
      ),
      calculateFee: (amount) => _calculateFees(
        amount: amount,
        type: type,
      ),
      exchangeRate: '1 USDC = 1 USDC',
    );

    final submittedAmount = amount;

    if (submittedAmount is! CryptoAmount) return;

    final receiveAmount = await runWithLoader<Amount>(
      this,
      () async => _fetchFees(amount: submittedAmount, type: type)
          .letAsync((p) => p.receiveAmount),
    ) as FiatAmount;

    await sl<MoneygramOffRampOrderService>()
        .createMoneygramOrder(
      submittedAmount: submittedAmount,
      receiveAmount: receiveAmount,
      countryCode: profile.country.code,
    )
        .then((order) {
      switch (order) {
        case Left<Exception, String>():
          showCpErrorSnackbar(this, message: l10n.tryAgainLater);

        case Right<Exception, String>(:final value):
          OffRampOrderScreen.push(this, id: value);
      }
    });
  }

  Future<MoneygramLink?> _generateDepositLink({required double amount}) =>
      runWithLoader<MoneygramLink?>(this, () async {
        try {
          final wallet = sl<StellarWallet>();
          final stellarClient = sl<StellarClient>();

          final token = await stellarClient.fetchToken();

          final client = sl<MoneygramApiClient>();

          final response = await client.generateDepositUrl(
            MgWithdrawRequestDto(
              assetCode: 'USDC',
              account: wallet.keyPair.accountId,
              lang: locale.languageCode,
              amount: amount.toString(),
            ),
            token,
          );

          final url = '${response.url}&callback=postmessage';

          return (id: response.id, url: url, token: token);
        } on Exception catch (error) {
          reportError(error);

          return null;
        }
      });

  /// For [RampType.onRamp], fee is added to input amount,
  /// for [RampType.offRamp], fee is taken from input amount
  ///
  /// Since [RampType.onRamp] fee is added, we show total amount to pay
  Future<Either<Exception, Amount>> _calculateReceiveAmount({
    required Amount amount,
    required RampType type,
  }) async {
    final fees = await _fetchFees(
      amount: amount,
      type: type,
    );

    return Either.right(fees.receiveAmount);
  }

  Future<Either<Exception, RampFees>> _calculateFees({
    required Amount amount,
    required RampType type,
  }) async {
    final fees = await _fetchFees(
      amount: amount,
      type: type,
    );

    final totalFees = switch (type) {
      RampType.onRamp => fees.bridgeFee,
      RampType.offRamp => fees.moneygramFee + fees.bridgeFee,
    };

    final bridgeFee = fees.bridgeFee.format(locale, maxDecimals: 2);
    final moneygramFee = fees.moneygramFee.format(locale, maxDecimals: 2);

    final partnerFee = switch (type) {
      RampType.onRamp => bridgeFee,
      RampType.offRamp => '$moneygramFee + $bridgeFee',
    };

    final extraFee = switch (type) {
      RampType.onRamp => fees.moneygramFee,
      RampType.offRamp => null,
    };

    return Either.right(
      (
        ourFee: null,
        partnerFee: partnerFee,
        totalFee: totalFees,
        extraFee: extraFee,
      ),
    );
  }

  Future<({Amount receiveAmount, Amount moneygramFee, Amount bridgeFee})>
      _fetchFees({
    required Amount amount,
    required RampType type,
  }) async {
    final client = sl<EspressoCashClient>();

    final fee = await client.calculateMoneygramFee(
      MoneygramFeeRequestDto(
        type: type.toDto(),
        amount: amount.decimal.toString(),
      ),
    );

    return (
      receiveAmount: Amount.fromDecimal(
        value: Decimal.parse(fee.totalAmount),
        currency: switch (type) {
          RampType.onRamp => Currency.usdc,
          RampType.offRamp => Currency.usd
        },
      ),
      moneygramFee: Amount.fromDecimal(
        value: Decimal.parse(fee.moneygramFee),
        currency: switch (type) {
          RampType.onRamp => Currency.usd,
          RampType.offRamp => Currency.usdc
        },
      ),
      bridgeFee: Amount.fromDecimal(
        value: Decimal.parse(fee.bridgeFee),
        currency: Currency.usdc,
      ),
    );
  }
}

extension on RampType {
  RampTypeDto toDto() => switch (this) {
        RampType.onRamp => RampTypeDto.onRamp,
        RampType.offRamp => RampTypeDto.offRamp
      };
}
