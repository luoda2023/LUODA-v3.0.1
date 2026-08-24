import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../common.dart';
import '../../consts.dart';

/// VIP 功能页 — 内嵌 WebView 浏览 VIP 会员中心网页，并注入 CSS
/// 让滚动条始终可见（手机端 WebView 默认不显示滚动条滑块，
/// 用户体验像没有滚动指示；注入 `::-webkit-scrollbar` 样式后
/// 长内容可上下滚动并看到滚动条）。
class VipFeaturesPage extends StatefulWidget {
 final EdgeInsets? menuPadding;
 const VipFeaturesPage({Key? key, this.menuPadding}) : super(key: key);

 @override
 State<VipFeaturesPage> createState() => _VipFeaturesPageState();
}

class _VipFeaturesPageState extends State<VipFeaturesPage>
 with AutomaticKeepAliveClientMixin {
 late final WebViewController _controller;
 bool _loading = true;
 String? _loadError;

 /// CSS injected after page load to force a visible, touch-friendly
 /// vertical scrollbar inside the WebView.
 static const _scrollbarCss = """
 (function() {
 var s = document.getElementById('__luoda_scrollbar');
 if (s) return;
 s = document.createElement('style');
 s.id = '__luoda_scrollbar';
 s.textContent = [
 '::-webkit-scrollbar { width: 8px; height: 8px; }',
 '::-webkit-scrollbar-track { background: rgba(0,0,0,0.06); }',
 '::-webkit-scrollbar-thumb { background: rgba(128,128,128,0.5); border-radius: 4px; }',
 '::-webkit-scrollbar-thumb:hover { background: rgba(128,128,128,0.8); }',
 'html { scrollbar-width: thin; scrollbar-color: rgba(128,128,128,0.5) rgba(0,0,0,0.06); }'
 ].join('\\n');
 document.head.appendChild(s);
 })();
 """;

 @override
 bool get wantKeepAlive => true;

 @override
 void initState() {
 super.initState();
 _controller = WebViewController()
 ..setJavaScriptMode(JavaScriptMode.unrestricted)
 ..setNavigationDelegate(
 NavigationDelegate(
 onPageStarted: (_) {
 if (mounted) setState(() => _loading = true);
 },
 onPageFinished: (_) {
 _injectScrollbarCss();
 if (mounted) setState(() => _loading = false);
 },
 onWebResourceError: (e) {
 if (mounted) {
 setState(() {
 _loading = false;
 _loadError = e.description;
 });
 }
 },
 ),
 )
 ..loadRequest(Uri.parse(kVipPageUrl));
 }

 Future<void> _injectScrollbarCss() async {
 try {
 await _controller.runJavaScript(_scrollbarCss);
 } catch (_) {
 // Non-fatal — scrollbar is a convenience, not critical.
 }
 }

 @override
 Widget build(BuildContext context) {
 super.build(context);
 return Stack(
 children: [
 Positioned.fill(
 child: _loadError != null
 ? _buildErrorView()
 : WebViewWidget(controller: _controller),
 ),
 if (_loading)
 const Center(child: CircularProgressIndicator()),
 ],
 );
 }

 Widget _buildErrorView() {
 final textColor = Theme.of(context).textTheme.titleLarge?.color;
 return Center(
 child: Padding(
 padding: const EdgeInsets.all(32),
 child: Column(
 mainAxisAlignment: MainAxisAlignment.center,
 children: [
 Icon(Icons.cloud_off, size: 48, color: textColor?.withOpacity(0.4)),
 const SizedBox(height: 12),
 Text(
 translate('Failed to load VIP page'),
 style: TextStyle(fontSize: 16, color: textColor),
 ),
 const SizedBox(height: 8),
 Text(
 translate('Please check your network and try again'),
 style: TextStyle(
 fontSize: 13,
 color: textColor?.withOpacity(0.5),
 ),
 ),
 const SizedBox(height: 16),
 ElevatedButton(
 onPressed: () {
 if (mounted) {
 setState(() {
 _loading = true;
 _loadError = null;
 });
 _controller.reload();
 }
 },
 child: Text(translate('Retry')),
 ),
 ],
 ),
 ),
 );
 }
}
