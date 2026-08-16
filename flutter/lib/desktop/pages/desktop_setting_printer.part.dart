part of 'desktop_setting_page.dart';

class _Printer extends StatefulWidget {
  const _Printer({super.key});

  @override
  State<_Printer> createState() => __PrinterState();
}
class __PrinterState extends State<_Printer> {
  @override
  Widget build(BuildContext context) {
    final scrollController = ScrollController();
    return ListView(controller: scrollController, children: [
      outgoing(context),
      incoming(context),
    ]).marginOnly(bottom: _kListViewBottomMargin);
  }

  Widget outgoing(BuildContext context) {
    final isSupportPrinterDriver =
        bind.mainGetCommonSync(key: 'is-support-printer-driver') == 'true';

    Widget tipOsNotSupported() {
      return Align(
        alignment: Alignment.topLeft,
        child: Text(translate('printer-os-requirement-tip')),
      ).marginOnly(left: _kCardLeftMargin);
    }

    Widget tipClientNotInstalled() {
      return Align(
        alignment: Alignment.topLeft,
        child:
            Text(translate('printer-requires-installed-{$appName}-client-tip')),
      ).marginOnly(left: _kCardLeftMargin);
    }

    Widget tipPrinterNotInstalled() {
      final failedMsg = ''.obs;
      platformFFI.registerEventHandler(
          'install-printer-res', 'install-printer-res', (evt) async {
        if (evt['success'] as bool) {
          setState(() {});
        } else {
          failedMsg.value = evt['msg'] as String;
        }
      }, replace: true);
      return Column(children: [
        Obx(
          () => failedMsg.value.isNotEmpty
              ? Offstage()
              : Align(
                  alignment: Alignment.topLeft,
                  child: Text(translate('printer-{$appName}-not-installed-tip'))
                      .marginOnly(bottom: 10.0),
                ),
        ),
        Obx(
          () => failedMsg.value.isEmpty
              ? Offstage()
              : Align(
                  alignment: Alignment.topLeft,
                  child: Text(failedMsg.value,
                          style: DefaultTextStyle.of(context)
                              .style
                              .copyWith(color: Colors.red))
                      .marginOnly(bottom: 10.0)),
        ),
        _Button('Install {$appName} Printer', () {
          failedMsg.value = '';
          bind.mainSetCommon(key: 'install-printer', value: '');
        })
      ]).marginOnly(left: _kCardLeftMargin, bottom: 2.0);
    }

    Widget tipReady() {
      return Align(
        alignment: Alignment.topLeft,
        child: Text(translate('printer-{$appName}-ready-tip')),
      ).marginOnly(left: _kCardLeftMargin);
    }

    final installed = bind.mainIsInstalled();
    // `is-printer-installed` may fail, but it's rare case.
    // Add additional error message here if it's really needed.
    final isPrinterInstalled =
        bind.mainGetCommonSync(key: 'is-printer-installed') == 'true';

    final List<Widget> children = [];
    if (!isSupportPrinterDriver) {
      children.add(tipOsNotSupported());
    } else {
      children.addAll([
        if (!installed) tipClientNotInstalled(),
        if (installed && !isPrinterInstalled) tipPrinterNotInstalled(),
        if (installed && isPrinterInstalled) tipReady()
      ]);
    }
    return _Card(title: translate('Outgoing Print Jobs'), children: children);
  }

  Widget incoming(BuildContext context) {
    onRadioChanged(String value) async {
      await bind.mainSetLocalOption(
          key: kKeyPrinterIncomingJobAction, value: value);
      setState(() {});
    }

    PrinterOptions printerOptions = PrinterOptions.load();
    return _Card(title: translate('Incoming Print Jobs'), children: [
      _Radio(context,
          value: kValuePrinterIncomingJobDismiss,
          groupValue: printerOptions.action,
          label: translate('Dismiss'),
          onChanged: onRadioChanged),
      _Radio(context,
          value: kValuePrinterIncomingJobDefault,
          groupValue: printerOptions.action,
          label: translate('use-the-default-printer-tip'),
          onChanged: onRadioChanged),
      _Radio(context,
          value: kValuePrinterIncomingJobSelected,
          groupValue: printerOptions.action,
          label: translate('use-the-selected-printer-tip'),
          onChanged: onRadioChanged),
      if (printerOptions.printerNames.isNotEmpty)
        ComboBox(
          initialKey: printerOptions.printerName,
          keys: printerOptions.printerNames,
          values: printerOptions.printerNames,
          enabled: printerOptions.action == kValuePrinterIncomingJobSelected,
          onChanged: (value) async {
            await bind.mainSetLocalOption(
                key: kKeyPrinterSelected, value: value);
            setState(() {});
          },
        ).marginOnly(left: 10),
      _OptionCheckBox(
        context,
        'auto-print-tip',
        kKeyPrinterAllowAutoPrint,
        isServer: false,
        enabled: printerOptions.action != kValuePrinterIncomingJobDismiss,
      )
    ]);
  }
}
