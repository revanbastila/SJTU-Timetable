/// Identifies the Canvas dashboard routes where the card/list switch exists.
bool isCanvasDashboardUri(Uri? uri) {
  if (uri == null || uri.scheme != 'https' || uri.host != 'oc.sjtu.edu.cn') {
    return false;
  }
  final path = uri.path.replaceFirst(RegExp(r'/+$'), '').toLowerCase();
  return path.isEmpty || path == '/dashboard';
}

/// A one-shot dashboard preference repair. It only switches an explicitly
/// active List View to Card View; it never clicks planner/Today controls or
/// scrolls the page. Once the dashboard is ready, users can change the view.
const canvasDashboardCardViewScript = r'''(() => {
  if (window.__sjtuCanvasCardViewCheckInstalled) return true;
  window.__sjtuCanvasCardViewCheckInstalled = true;
  const clean = element => String([
    element?.innerText, element?.textContent, element?.getAttribute?.('aria-label'),
    element?.title, element?.dataset?.testid
  ].filter(Boolean).join(' ')).replace(/\s+/g, ' ').trim().toLowerCase();
  const selected = element => element && (
    element.getAttribute('aria-pressed') === 'true' ||
    element.getAttribute('aria-selected') === 'true' ||
    /active|selected|current/i.test(String(element.className || ''))
  );
  let attempts = 0;
  const timer = setInterval(() => {
    attempts++;
    const controls = [...document.querySelectorAll(
      'button, [role="button"], [role="tab"], a')];
    const card = controls.find(element =>
      /card view|cards view|卡片视图|课程卡片/.test(clean(element)));
    const list = controls.find(element =>
      /list view|列表视图|列表/.test(clean(element)));
    if (card && list) {
      if (selected(list) && !selected(card)) card.click();
      clearInterval(timer);
    } else if (attempts >= 40) {
      clearInterval(timer);
    }
  }, 250);
  return true;
})()''';
