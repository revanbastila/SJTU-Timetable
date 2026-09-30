import 'dart:convert';

import 'package:webview_flutter/webview_flutter.dart';

enum SchoolPageKind { target, login, challenge, transition, outside }

class SchoolPageInspection {
  const SchoolPageInspection(this.kind, this.uri);

  final SchoolPageKind kind;
  final Uri? uri;
}

class SchoolWebAuthenticator {
  const SchoolWebAuthenticator(this.controller);

  final WebViewController controller;

  static bool isAllowedHost(String host, String targetHost) =>
      host == targetHost ||
      host == 'sjtu.edu.cn' ||
      host.endsWith('.sjtu.edu.cn');

  Future<SchoolPageInspection> inspect(String targetHost,
      {bool allowHttpTarget = false}) async {
    final uri = Uri.tryParse(await controller.currentUrl() ?? '');
    if (uri == null ||
        (uri.scheme != 'https' &&
            !(allowHttpTarget &&
                uri.scheme == 'http' &&
                uri.host == targetHost))) {
      return SchoolPageInspection(SchoolPageKind.outside, uri);
    }
    final schoolHost = isAllowedHost(uri.host, targetHost);
    if (!schoolHost) {
      return SchoolPageInspection(SchoolPageKind.outside, uri);
    }

    final raw = await controller.runJavaScriptReturningResult(r'''
      (() => {
        const visible = element => !!element &&
          (element.offsetWidth || element.offsetHeight ||
           element.getClientRects().length);
        const password = [...document.querySelectorAll('input[type=password]')]
          .find(visible);
        const challengeNode = [...document.querySelectorAll(
          'input,iframe,[class*="captcha" i],[id*="captcha" i],'
          + '[class*="otp" i],[id*="otp" i]')].find(element => {
            if (!visible(element)) return false;
            const value = [element.name, element.id, element.placeholder,
              element.getAttribute?.('aria-label'), element.src]
              .filter(Boolean).join(' ');
            return /captcha|验证码|动态码|二次验证|otp|mfa/i.test(value);
          });
        const body = (document.body?.innerText || '').slice(0, 12000);
        const challengeText = /请输入验证码|图形验证码|动态验证码|二次验证|多因素认证/i
          .test(body);
        return JSON.stringify({
          hasPassword: !!password,
          hasChallenge: !!challengeNode || challengeText
        });
      })()
    ''');
    final state = _jsonMap(raw);
    final hasPassword = state['hasPassword'] == true;
    final hasChallenge = state['hasChallenge'] == true;
    if (hasChallenge) {
      return SchoolPageInspection(SchoolPageKind.challenge, uri);
    }
    if (hasPassword) {
      return SchoolPageInspection(SchoolPageKind.login, uri);
    }
    if (uri.host == targetHost) {
      return SchoolPageInspection(SchoolPageKind.target, uri);
    }
    return SchoolPageInspection(SchoolPageKind.transition, uri);
  }

  Future<bool> submit(String username, String password) async {
    if (username.isEmpty || password.isEmpty) return false;
    final accountJson = jsonEncode(username);
    final passwordJson = jsonEncode(password);
    final raw = await controller.runJavaScriptReturningResult('''
      (() => {
        const visible = element => !!element &&
          (element.offsetWidth || element.offsetHeight ||
           element.getClientRects().length);
        const inputs = [...document.querySelectorAll('input')].filter(visible);
        const p = inputs.find(element => element.type === 'password');
        const u = inputs.find(element => /user|account|login/i.test(
          (element.name || '') + (element.id || '')) &&
          ['text', 'email'].includes(element.type)) ||
          inputs.find(element => element.type === 'text' ||
            element.type === 'email');
        if (!u || !p) return false;
        const setValue = (element, value) => {
          const setter = Object.getOwnPropertyDescriptor(
            HTMLInputElement.prototype, 'value')?.set;
          if (setter) setter.call(element, value); else element.value = value;
          element.dispatchEvent(new Event('input', {bubbles: true}));
          element.dispatchEvent(new Event('change', {bubbles: true}));
        };
        setValue(u, $accountJson);
        setValue(p, $passwordJson);
        const form = p.form || u.form;
        const submit = form?.querySelector('[type=submit]') ||
          [...document.querySelectorAll('button,input,[role=button]')]
            .filter(visible).find(element => /登录|login|sign in/i.test(
              (element.innerText || '') + (element.value || '') +
              (element.getAttribute?.('aria-label') || '')));
        if (submit) submit.click();
        else if (form?.requestSubmit) form.requestSubmit();
        else if (form) form.submit();
        else return false;
        return true;
      })()
    ''');
    return raw == true || '$raw' == 'true';
  }

  Future<bool> fill(String username, String password) async {
    if (username.isEmpty || password.isEmpty) return false;
    final accountJson = jsonEncode(username);
    final passwordJson = jsonEncode(password);
    final raw = await controller.runJavaScriptReturningResult('''
      (() => {
        const visible = element => !!element &&
          (element.offsetWidth || element.offsetHeight ||
           element.getClientRects().length);
        const inputs = [...document.querySelectorAll('input')].filter(visible);
        const p = inputs.find(element => element.type === 'password');
        const u = inputs.find(element => /user|account|login/i.test(
          (element.name || '') + (element.id || '')) &&
          ['text', 'email'].includes(element.type)) ||
          inputs.find(element => element.type === 'text' ||
            element.type === 'email');
        if (!u || !p) return false;
        const setValue = (element, value) => {
          const setter = Object.getOwnPropertyDescriptor(
            HTMLInputElement.prototype, 'value')?.set;
          if (setter) setter.call(element, value); else element.value = value;
          element.dispatchEvent(new Event('input', {bubbles: true}));
          element.dispatchEvent(new Event('change', {bubbles: true}));
        };
        setValue(u, $accountJson);
        setValue(p, $passwordJson);
        return true;
      })()
    ''');
    return raw == true || '$raw' == 'true';
  }

  Future<bool> clickSsoButton({
    int attempts = 1,
    Duration delay = const Duration(milliseconds: 350),
    bool Function()? shouldContinue,
  }) async {
    for (var attempt = 0; attempt < attempts; attempt++) {
      if (shouldContinue?.call() == false) return false;
      final raw = await controller.runJavaScriptReturningResult(r'''
      (() => {
        const visible = element => !!element &&
          (element.offsetWidth || element.offsetHeight ||
           element.getClientRects().length);
        const nodes = [...document.querySelectorAll(
          'a,button,input[type=submit],input[type=button],[role=button]')]
          .filter(visible);
        const details = element => [element.innerText, element.href,
          element.value, element.title, element.getAttribute?.('aria-label'),
          element.querySelector?.('img')?.src,
          element.querySelector?.('[id*=jaccount i]')?.id]
          .filter(Boolean).join(' ');
        const positive = element =>
          /jaccount|统一身份|openid_connect|oauth|saml|shibboleth/i
            .test(details(element));
        const negative = element =>
          /非\s*jaccount|校外|outside|non[-\s]?jaccount/i
            .test(details(element));
        const sso = nodes.find(element => positive(element) && !negative(element));
        if (!sso) return false;
        sso.click();
        return true;
      })()
    ''');
      if (raw == true || '$raw' == 'true') return true;
      if (attempt + 1 < attempts) await Future<void>.delayed(delay);
    }
    return false;
  }

  /// Selects Canvas' jAccount entry on the local login chooser.
  ///
  /// Canvas has used both links and JavaScript-backed cards for this entry.
  /// Keep this separate from the generic SSO selector so a nearby external
  /// login option can never be chosen accidentally.
  Future<bool> clickCanvasJaccount({
    int attempts = 10,
    Duration delay = const Duration(milliseconds: 300),
    bool Function()? shouldContinue,
  }) async {
    for (var attempt = 0; attempt < attempts; attempt++) {
      if (shouldContinue?.call() == false) return false;
      final raw = await controller.runJavaScriptReturningResult(r'''
      (() => {
        const visible = element => !!element &&
          (element.offsetWidth || element.offsetHeight ||
           element.getClientRects().length);
        const compact = value => String(value || '')
          .replace(/\s+/g, '').toLowerCase();
        const describe = element => compact([
          element.innerText, element.textContent, element.href, element.value,
          element.title, element.alt, element.id, element.className,
          element.getAttribute?.('aria-label'), element.getAttribute?.('data-href'),
          element.src, element.querySelector?.('img')?.alt,
          element.querySelector?.('img')?.src
        ].filter(Boolean).join(' '));
        const forbidden = text =>
          /非jaccount|校外|outside|non-?jaccount|external/.test(text);
        const nodes = [...document.querySelectorAll(
          'a,button,[role=button],input,div,span,img')].filter(visible);
        const scored = nodes.map(element => {
          const text = describe(element);
          if (!text || forbidden(text)) return {element, score: -1};
          let score = 0;
          if (/^(使用)?jaccount(登录)?$/.test(compact(element.innerText || element.value || element.alt))) score += 100;
          if (/jaccount登录|使用jaccount/.test(text)) score += 70;
          if (/openid_connect|login\/openid|jaccount/.test(text)) score += 35;
          if (element.matches('a,button,[role=button],input')) score += 8;
          return {element, score};
        }).filter(item => item.score > 0)
          .sort((a, b) => b.score - a.score);
        if (!scored.length) return false;
        let target = scored[0].element;
        const clickable = target.closest?.('a,button,[role=button]');
        if (clickable && !forbidden(describe(clickable))) target = clickable;
        else {
          let parent = target.parentElement;
          for (let depth = 0; parent && depth < 4; depth++, parent = parent.parentElement) {
            const style = getComputedStyle(parent);
            if (parent.onclick || parent.tabIndex >= 0 || style.cursor === 'pointer') {
              if (!forbidden(describe(parent))) target = parent;
              break;
            }
          }
        }
        target.scrollIntoView?.({block: 'center'});
        ['pointerdown', 'mousedown', 'pointerup', 'mouseup'].forEach(type =>
          target.dispatchEvent(new MouseEvent(type, {bubbles: true, cancelable: true})));
        target.click();
        return true;
      })()
    ''');
      if (raw == true || '$raw' == 'true') return true;
      if (attempt + 1 < attempts) await Future<void>.delayed(delay);
    }
    return false;
  }

  Map<String, dynamic> _jsonMap(Object value) {
    dynamic decoded = value;
    for (var attempt = 0; attempt < 2 && decoded is String; attempt++) {
      try {
        decoded = jsonDecode(decoded);
      } catch (_) {
        break;
      }
    }
    return decoded is Map ? Map<String, dynamic>.from(decoded) : const {};
  }
}
