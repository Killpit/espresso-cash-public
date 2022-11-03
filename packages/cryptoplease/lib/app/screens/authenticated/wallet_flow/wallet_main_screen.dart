import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';

import '../../../../core/amount.dart';
import '../../../../gen/assets.gen.dart';
import '../../../../l10n/device_locale.dart';
import '../../../../l10n/l10n.dart';
import '../../../../ui/amount_keypad/amount_keypad.dart';
import '../../../../ui/amount_with_equivalent.dart';
import '../../../../ui/button.dart';
import '../../../../ui/navigation_bar/navigation_bar.dart';
import '../../../../ui/number_formatter.dart';
import '../../../../ui/usdc_info.dart';

class WalletMainScreen extends StatefulWidget {
  const WalletMainScreen({
    super.key,
    required this.onScan,
    required this.onAmountChanged,
    required this.onRequest,
    required this.onPay,
    required this.amount,
    this.shakeKey,
    this.error = '',
  });

  final VoidCallback onScan;
  final VoidCallback onRequest;
  final VoidCallback onPay;
  final ValueSetter<Decimal> onAmountChanged;
  final CryptoAmount amount;
  final Key? shakeKey;
  final String error;

  @override
  State<WalletMainScreen> createState() => _ScreenState();
}

class _ScreenState extends State<WalletMainScreen> {
  late final TextEditingController _amountController;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController();
    _amountController.addListener(_updateValue);
  }

  @override
  void dispose() {
    _amountController.removeListener(_updateValue);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant WalletMainScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    final newAmount = widget.amount.decimal;
    final locale = DeviceLocale.localeOf(context);
    final currentAmount = _amountController.text.toDecimalOrZero(locale);
    if (newAmount != oldWidget.amount.decimal && newAmount != currentAmount) {
      _amountController.text = newAmount.toString();
    }
  }

  void _updateValue() {
    final locale = DeviceLocale.localeOf(context);
    final amount = _amountController.text.toDecimalOrZero(locale);
    widget.onAmountChanged(amount);
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final height = MediaQuery.of(context).size.height;

    return Scaffold(
      appBar: _QrScannerAppBar(onQrScanner: widget.onScan),
      body: Column(
        children: [
          AmountWithEquivalent(
            inputController: _amountController,
            token: widget.amount.currency.token,
            collapsed: false,
            shakeKey: widget.shakeKey,
            error: widget.error,
          ),
          const SizedBox(height: 8),
          UsdcInfoWidget(
            isSmall: height < 700,
          ),
          Flexible(
            child: LayoutBuilder(
              builder: (context, constraints) => AmountKeypad(
                height: constraints.maxHeight,
                width: width,
                controller: _amountController,
                maxDecimals: 2,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Row(
              children: [
                Flexible(
                  child: CpButton(
                    text: context.l10n.receive,
                    minWidth: width,
                    onPressed: widget.onRequest,
                    size: CpButtonSize.big,
                  ),
                ),
                const SizedBox(width: 24),
                Flexible(
                  child: CpButton(
                    text: context.l10n.pay,
                    minWidth: width,
                    onPressed: widget.onPay,
                    size: CpButtonSize.big,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: cpNavigationBarheight + 24),
        ],
      ),
    );
  }
}

class _QrScannerAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _QrScannerAppBar({
    Key? key,
    required this.onQrScanner,
  }) : super(key: key);

  final VoidCallback onQrScanner;

  @override
  Size get preferredSize => const Size.fromHeight(2 * kToolbarHeight);

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(left: 28, top: 12),
          child: Row(
            children: [
              SizedBox.square(
                dimension: 26,
                child: IconButton(
                  onPressed: onQrScanner,
                  icon: Assets.icons.qrScanner.svg(height: 26),
                  padding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ),
      );
}