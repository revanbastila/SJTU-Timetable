import 'package:flutter/material.dart';

import '../models/app_theme.dart';
import '../state/app_controller.dart';
import 'portal_sync_page.dart';
import 'home_shell.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.app});
  final AppController app;
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _form = GlobalKey<FormState>();
  final _account = TextEditingController();
  final _password = TextEditingController();
  bool _remember = true;
  bool _obscure = true;
  bool _connecting = false;
  @override
  void initState() {
    super.initState();
    _account.text = widget.app.username;
  }

  @override
  void dispose() {
    _account.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (_connecting || !_form.currentState!.validate()) return;
    setState(() => _connecting = true);
    try {
      // A fast re-login must not race with the previous account's asynchronous
      // cookie/cache cleanup, otherwise the new jAccount session is erased.
      await widget.app.awaitSessionCleanup();
      if (!mounted) return;
      widget.app.retainSessionCredentials(
        _account.text.trim(),
        _password.text,
      );
      await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => PortalSyncPage(
              username: _account.text.trim(),
              password: _password.text,
              app: widget.app,
              rememberMe: _remember)));
      if (mounted && widget.app.loggedIn) {
        Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
                builder: (_) => HomeShell(
                      app: widget.app,
                      initializeCanvas: true,
                      showInitialCanvasHint: true,
                    )),
            (_) => false);
      }
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final header =
        widget.app.themeChoice.headerFor(Theme.of(context).brightness);
    return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: SafeArea(
            child: Center(
                child: SingleChildScrollView(
                    padding: const EdgeInsets.all(28),
                    child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: Form(
                            key: _form,
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.calendar_month_outlined,
                                      size: 48, color: accent),
                                  const SizedBox(height: 24),
                                  Text('交大课表',
                                      style: TextStyle(
                                          fontSize: 32,
                                          fontWeight: FontWeight.w700,
                                          color: header)),
                                  const SizedBox(height: 8),
                                  Text('使用 jAccount 连接你的课程',
                                      style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant)),
                                  const SizedBox(height: 40),
                                  TextFormField(
                                      controller: _account,
                                      autofillHints: const [
                                        AutofillHints.username
                                      ],
                                      decoration: const InputDecoration(
                                          labelText: 'jAccount账号',
                                          hintText: '请输入 jAccount 账号',
                                          prefixIcon:
                                              Icon(Icons.person_outline)),
                                      validator: (v) =>
                                          v == null || v.trim().isEmpty
                                              ? '请输入 jAccount 账号'
                                              : null),
                                  const SizedBox(height: 16),
                                  TextFormField(
                                      controller: _password,
                                      obscureText: _obscure,
                                      autofillHints: const [
                                        AutofillHints.password
                                      ],
                                      decoration: InputDecoration(
                                          labelText: '密码',
                                          prefixIcon:
                                              const Icon(Icons.lock_outline),
                                          suffixIcon: IconButton(
                                              onPressed: () => setState(
                                                  () => _obscure = !_obscure),
                                              icon: Icon(_obscure
                                                  ? Icons.visibility_outlined
                                                  : Icons
                                                      .visibility_off_outlined))),
                                      validator: (v) => v == null || v.isEmpty
                                          ? '请输入密码'
                                          : null),
                                  const SizedBox(height: 12),
                                  CheckboxListTile(
                                      contentPadding: EdgeInsets.zero,
                                      controlAffinity:
                                          ListTileControlAffinity.leading,
                                      value: _remember,
                                      onChanged: (v) => setState(
                                          () => _remember = v ?? false),
                                      title: const Text('记住本人'),
                                      subtitle:
                                          const Text('下次直接打开课表；学校登录过期时再验证')),
                                  const SizedBox(height: 20),
                                  SizedBox(
                                      width: double.infinity,
                                      height: 52,
                                      child: FilledButton(
                                          onPressed:
                                              _connecting ? null : _connect,
                                          child: Text(_connecting
                                              ? '正在准备登录…'
                                              : '登录并同步课表'))),
                                  const SizedBox(height: 16),
                                  Text('密码由系统安全存储加密保护，不会明文保存。',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant)),
                                ])))))));
  }
}
