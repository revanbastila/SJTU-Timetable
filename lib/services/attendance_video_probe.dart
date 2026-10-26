/// The clock is meaningful only for the same visible video and crop. A view
/// switch can keep the DOM node while replacing its stream or moving its bounds.
class AttendanceVideoSampling {
  String? _key;
  double? _time;

  void reset() {
    _key = null;
    _time = null;
  }

  bool accept(Map<String, dynamic> frame) {
    final key = frame['frameKey'];
    final time = (frame['time'] as num?)?.toDouble();
    final bounds = [
      for (final name in ['x', 'y', 'width', 'height'])
        (frame[name] as num?)?.toDouble(),
    ];
    if (frame['playing'] != true ||
        key is! String ||
        key.isEmpty ||
        time == null ||
        !time.isFinite ||
        time < 0 ||
        bounds.any((v) => v == null || !v.isFinite) ||
        bounds[0]! < 0 ||
        bounds[1]! < 0 ||
        bounds[2]! <= 0 ||
        bounds[3]! <= 0 ||
        bounds[0]! + bounds[2]! > 1.001 ||
        bounds[1]! + bounds[3]! > 1.001) {
      reset();
      return false;
    }
    final advancing = _key == key && _time != null && time > _time!;
    _key = key;
    _time = time;
    return advancing;
  }
}

/// Adapted from the actual SJTU play-center LivePlay/VideoPlay controls inspected
/// on 2026-10-26. These are player view assignments, not PPT slide thumbnails or
/// the separate audio-channel menu. No private Vue state or stream URLs are used.
const attendanceVideoProbe = r'''
(() => {
  const all = (selector, root=document) => [...root.querySelectorAll(selector)];
  const text = n => (n?.innerText || n?.textContent || '').replace(/\s+/g, '');
  const visible = n => {
    if (!n) return false;
    const r=n.getBoundingClientRect(), s=getComputedStyle(n);
    return r.width>1 && r.height>1 && r.right>0 && r.bottom>0 &&
      r.left<innerWidth && r.top<innerHeight && s.display!=='none' &&
      s.visibility!=='hidden' && Number(s.opacity)!==0;
  };
  const enabled = n => n && !n.disabled && n.getAttribute('aria-disabled')!=='true' &&
    !n.classList.contains('is-disabled');
  const selected = n => n && (n.classList.contains('active') ||
    n.getAttribute('aria-selected')==='true' || n.getAttribute('aria-pressed')==='true');
  const ppt = value => /^(PPT|电脑(画面|屏幕)?|电脑共享(画面|屏幕)?|屏幕共享|共享屏幕|演示(画面|屏幕))$/i.test(value);
  const state = window.__attendanceViewProbe ||= {
    started:Date.now(), phase:'discovering', manual:!!window.__attendanceManualView, attempted:new Set(),
    ids:new WeakMap(), nextId:0, revision:0, pending:null, settledAt:0,
  };
  if (!state.listening) {
    state.listening=true;
    const manual = event => {
      if (!event.isTrusted || !event.target?.closest) return;
      if (event.target.closest('.video-layout-control-popper,.video-layout-select-dropdown,'+
          '[title="切换大小屏"],[title="画中画"],.controller-wrapper,'+
          '.double-screen-switch,.select-channel-sheet')) {
        state.manual=true; state.phase='manual'; state.pending=null;
        state.revision++; state.settledAt=Date.now();
      }
    };
    document.addEventListener('pointerdown',manual,true);
    document.addEventListener('click',manual,true);
  }
  const now=Date.now();
  if (state.manual) state.phase='manual';
  let message='';
  const wait = message => JSON.stringify({playing:false,message,viewState:state.phase});
  // A play-center landing page may initially display a recording. Select its
  // actual live tab before considering any video, including a playing replay.
  const liveTabs=all('.play-link-tab,[role="tab"],.tab-item')
    .filter(n=>visible(n)&&text(n)==='直播');
  const replayTabs=all('.play-link-tab,[role="tab"],.tab-item')
    .filter(n=>visible(n)&&/^(点播|回放)$/.test(text(n))&&selected(n));
  if (replayTabs.length) {
    if (liveTabs.length===1 && !state.liveTabSelected) {
      state.liveTabSelected=true; liveTabs[0].click();
    }
    return wait('正在进入当前直播，不识别历史回放');
  }
  const layout=document.querySelector('.video-layout-control-popper');
  const mobile=document.querySelector('.live-detail-mobile');
  const mobileBar=mobile?.querySelector('.portrait-wrapper .controller-wrapper');
  const mobileSwitch=mobileBar?.querySelector('[role="switch"]');
  const sheet=all('.select-channel-sheet').find(visible);
  const mobileSingle = () => mobileSwitch && mobileSwitch.getAttribute('aria-checked')==='false' &&
    /单视角播放/.test(text(mobileBar));
  const sheetPpt = () => sheet && all('.van-cell',sheet).find(n=>ppt(text(n.querySelector('.van-cell__title'))));
  const mobileVideo = () => all('video',mobile || document).find(n=>
    !n.closest('.second-player-wrapper') && visible(n));
  const rows=layout ? all('.video-layout-select-row',layout) : [];
  const row = kind => rows.find(n => new RegExp('^'+kind+'屏幕(演示|展示)$').test(
    text(n.querySelector('.video-layout-select-row__label'))));
  const primary=row('主'), secondary=row('副');
  const assignment = n => text(n?.querySelector('.el-select__placeholder'));
  const single=layout && all('button.video-layout-segment__item',layout).find(n=>text(n)==='单屏');
  const action = (key,node,done) => {
    if (!enabled(node) || state.attempted.has(key)) return false;
    state.attempted.add(key); state.phase='switching';
    state.pending={key,done,until:now+4000}; state.revision++;state.settledAt=now;
    node.click(); return true;
  };
  const confirmed = key => {
    if (key==='mobileSingle') return mobileSingle();
    if (key==='mobileMenu') return !!sheet;
    if (key==='mobilePpt') return sheetPpt()?.classList.contains('active');
    if (key==='mobileApplied') {
      const v=mobileVideo();
      return !sheet && mobileSingle() && v && (state.mobileAlreadyPpt ||
        v!==state.mobileBeforeVideo || v.currentSrc!==state.mobileBeforeSource ||
        v.currentTime<state.mobileBeforeTime);
    }
    return key==='ppt' ? ppt(assignment(primary)) : selected(single);
  };
  if (!state.manual && !['ready','fallback'].includes(state.phase)) {
    if (state.pending) {
      if (confirmed(state.pending.done)) {
        if (state.pending.done==='mobileApplied') state.phase='ready';
        state.pending=null; state.settledAt=now; state.revision++;
      } else if (now<state.pending.until) {
        return wait('正在切换 PPT／电脑画面…');
      } else {
        state.pending=null; state.phase='fallback';
        state.reason='PPT／电脑画面自动切换未成功，继续识别当前直播，可手动切换';
      }
    }
    if (state.phase!=='fallback') {
      if (mobileBar && mobileSwitch && state.phase!=='ready') {
        // The mobile player uses a separate single/dual switch and a Vant
        // channel sheet. Choose single first, so choosing PPT cannot leave a
        // teacher camera assigned as the primary view of a two-channel group.
        if (!mobileSingle()) {
          if (mobileSwitch.getAttribute('aria-checked')==='true' &&
              action('mobileSingle',mobileSwitch,'mobileSingle'))
            return wait('正在切换单视角播放…');
        } else if (!state.attempted.has('mobileConfirm')) {
          if (!sheet) {
            const view=all('button',mobileBar).find(n=>text(n)==='视角'&&visible(n));
            if (action('mobileMenu',view,'mobileMenu')) return wait('正在打开直播视角选择…');
          } else {
            const option=sheetPpt();
            if (option && enabled(option)) {
              if (!state.attempted.has('mobilePpt'))
                state.mobileAlreadyPpt=option.classList.contains('active');
              if (!option.classList.contains('active')) {
                if (action('mobilePpt',option,'mobilePpt')) return wait('正在选择 PPT／电脑画面…');
              } else {
                const v=mobileVideo();
                state.mobileBeforeVideo=v; state.mobileBeforeSource=v?.currentSrc;
                state.mobileBeforeTime=v?.currentTime;
                const confirm=all('button',sheet).find(n=>text(n)==='确定');
                if (action('mobileConfirm',confirm,'mobileApplied')) return wait('正在应用 PPT／电脑画面…');
              }
            }
          }
        }
      } else if (layout && primary && state.phase!=='ready') {
        if (!ppt(assignment(primary))) {
          // PPT already assigned to the secondary view is disabled in the main
          // selector. Use the player's own swap action, then verify its labels.
          if (ppt(assignment(secondary))) {
            if (action('swap',layout.querySelector('.video-layout-switch-btn'),'ppt'))
              return wait('正在将 PPT／电脑画面切到主屏…');
          } else {
            const options=all('[role="option"]',primary).filter(n=>ppt(text(n))&&enabled(n));
            if (options.length===1 && action('ppt',options[0],'ppt'))
              return wait('正在选择 PPT／电脑画面…');
          }
        } else if (single && !selected(single)) {
          if (action('single',single,'single')) return wait('正在切换单屏显示…');
        } else {
          state.phase='ready'; state.settledAt=now; state.revision++;
        }
      }
      if (state.phase!=='ready') {
        if (now-state.started<12000) return wait('正在查找 PPT／电脑画面入口…');
        state.phase='fallback';
        state.reason='未找到可用的 PPT／电脑画面入口，继续识别当前直播，可手动切换';
      }
    }
  }
  if (state.phase==='fallback' && sheet && !state.closedSheet) {
    const close=sheet.querySelector('.van-action-sheet__cancel,.van-action-sheet__close');
    if (enabled(close)) {state.closedSheet=true; close.click();state.revision++;state.settledAt=now;}
  }
  if (state.phase==='ready' && !state.cleaned) {
    state.cleaned=true;
    // Use observed player controls/events; do not remove arbitrary page nodes.
    const module=document.querySelector('#playerModule');
    if (module?.querySelector('#pptHorizontalWrapper,.ppt-horizontal-wrapper')) {
      const collapse=all('button',module).filter(n=>text(n)==='收起'&&visible(n)&&enabled(n));
      if (collapse.length===1) collapse[0].click();
    }
    all('.jkp-hover-wrap,.control-popper').forEach(n=>
      n.dispatchEvent(new MouseEvent('mouseleave',{bubbles:false})));
    state.revision++; state.settledAt=now;
    return wait('已选择 PPT／电脑画面，正在等待画面稳定…');
  }
  if (now-state.settledAt<600) return wait('正在等待切换后的直播画面…');
  message=state.manual ? '使用手动选择的直播画面识别' : state.phase==='ready' ?
    '已选择 PPT／电脑画面，正在识别二维码' : state.reason;
  const videos=all('video').filter(n=>visible(n)&&n.getBoundingClientRect().width>32&&
    n.getBoundingClientRect().height>32);
  const primaryVideo=videos.find(n=>n.closest('.jkp-stage-layout__primary')) ||
    (mobile && videos.find(n=>!n.closest('.second-player-wrapper')));
  // Prefer the displayed main view, even if it is buffering. Never sample a
  // playing camera thumbnail while waiting for the selected PPT to become ready.
  const video=primaryVideo || videos.sort((a,b)=>{
    const x=a.getBoundingClientRect(),y=b.getBoundingClientRect();
    return y.width*y.height-x.width*x.height;
  })[0];
  if (video && !video.paused && video.readyState>=2 && video.videoWidth>0 && video.videoHeight>0) {
    const r=video.getBoundingClientRect();
    const left=Math.max(0,r.left),top=Math.max(0,r.top);
    const right=Math.min(innerWidth,r.right),bottom=Math.min(innerHeight,r.bottom);
    if (right-left<=32 || bottom-top<=32) return wait('请将直播画面移到可见区域');
    if (!state.ids.has(video)) state.ids.set(video,++state.nextId);
    // Stream changes get an opaque revision; signed media URLs never leave JS.
    if (state.lastVideo!==video || state.lastSource!==video.currentSrc) {
      state.lastVideo=video; state.lastSource=video.currentSrc; state.revision++;
    }
    return JSON.stringify({playing:true,time:video.currentTime,message,viewState:state.phase,
      frameKey:[state.ids.get(video),state.revision,left,top,right,bottom,
        video.videoWidth,video.videoHeight].join(':'),
      x:left/innerWidth,y:top/innerHeight,width:(right-left)/innerWidth,height:(bottom-top)/innerHeight});
  }
  const buttons=all('a,button,[role=tab],[role=button],.tab-item');
  const live=buttons.find(n=>visible(n)&&text(n)==='直播');
  if (live && !state.liveTabSelected && !selected(live)) {
    state.liveTabSelected=true; live.click(); return wait('正在进入直播');
  }
  const ongoing=buttons.filter(n=>visible(n)&&/直播中/.test(text(n))&&!/回放|历史|未开始|已结束/.test(text(n)));
  if (ongoing.length===1 && !state.liveSelected) {
    state.liveSelected=true; ongoing[0].click(); return wait('正在播放当前直播');
  }
  if (video && !state.playTried) {
    state.playTried=true; video.play().catch(()=>{});
  }
  const frames=all('iframe').filter(visible).map(n=>n.src).filter(u=>/^https:\/\//.test(u));
  return JSON.stringify({playing:false,frame:frames.length===1?frames[0]:null,
    viewState:state.phase,message:ongoing.length>1?'存在多个直播，请在页面中选择当前课程':
      (message ? message+'；等待直播开始或点击播放' : '等待直播开始或点击播放')});
})()
''';

/// An explicit in-app manual override also works on touch-only players where
/// their layout controls may not dispatch pointer events consistently.
const attendanceUseCurrentView = r'''
(() => { window.__attendanceManualView=true; const s=window.__attendanceViewProbe; if (s && !s.manual) {
  s.manual=true; s.phase='manual'; s.pending=null; s.revision++; s.settledAt=Date.now();
} })()
''';
