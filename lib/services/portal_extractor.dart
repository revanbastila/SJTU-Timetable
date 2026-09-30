// Installed after every portal page load. Course-related fetch/XHR responses
// stay in WebView memory only and are consumed when the user taps 读取课表.
const portalCaptureBootstrapScript = r"""
(() => {
  if (window.__jtCaptureInstalled) return true;
  window.__jtCaptureInstalled = true;
  window.__jtCoursePayloads = window.__jtCoursePayloads || [];
  const relevant = url =>
    /course|schedule|xskb|kbxx|kcb|jxb|class|kecheng|paike/i.test(String(url || ''));
  const keep = (url, data) => {
    if (!relevant(url) || data == null) return;
    try {
      const serialized = JSON.stringify(data);
      if (serialized.length > 2000000) return;
      window.__jtCoursePayloads.push({url: String(url || ''), data});
      if (window.__jtCoursePayloads.length > 60) {
        window.__jtCoursePayloads.splice(
          0, window.__jtCoursePayloads.length - 60);
      }
    } catch (_) {}
  };

  const originalFetch = window.fetch;
  if (originalFetch) {
    window.fetch = async function(...args) {
      const response = await originalFetch.apply(this, args);
      try {
        const url = response.url || args[0]?.url || args[0];
        if (relevant(url)) {
          response.clone().json().then(data => keep(url, data)).catch(() => {});
        }
      } catch (_) {}
      return response;
    };
  }

  const originalOpen = XMLHttpRequest.prototype.open;
  const originalSend = XMLHttpRequest.prototype.send;
  XMLHttpRequest.prototype.open = function(method, url, ...rest) {
    this.__jtUrl = url;
    return originalOpen.call(this, method, url, ...rest);
  };
  XMLHttpRequest.prototype.send = function(...args) {
    if (!this.__jtObserved) {
      this.__jtObserved = true;
      this.addEventListener('load', () => {
        if (!relevant(this.__jtUrl)) return;
        try { keep(this.__jtUrl, JSON.parse(this.responseText)); } catch (_) {}
      });
    }
    return originalSend.apply(this, args);
  };
  return true;
})()
""";

// The public portal shell is reachable without authentication, so merely
// landing on yjsxk.sjtu.edu.cn does not prove that a jAccount session exists.
// This probes the same public-info endpoint used by the official page and
// exposes loginUserId without retaining any credentials in JavaScript.
const portalSessionProbeScript = r"""
(() => {
  const text = value => String(value ?? '').trim();
  const studentNumber = info => {
    if (!info || typeof info !== 'object') return '';
    const sources = [info, info.userInfo, info.studentInfo,
      info.student, info.xsxx, info.data].filter(
        value => value && typeof value === 'object');
    for (const source of sources) {
      for (const key of ['xh', 'XH', 'studentNo', 'studentNumber',
        'studentId', 'userCode', 'loginUserId']) {
        const value = text(source[key]);
        if (/^\d{8,15}$/.test(value)) return value;
      }
    }
    return '';
  };
  const studentName = info => {
    if (!info || typeof info !== 'object') return '';
    const sources = [info, info.userInfo, info.studentInfo,
      info.student, info.xsxx, info.data].filter(
        value => value && typeof value === 'object');
    for (const source of sources) {
      for (const key of ['xm', 'XM', 'name', 'studentName',
        'realName', '姓名']) {
        const value = text(source[key]);
        if (/^[\u4e00-\u9fff·]{2,12}$/.test(value)) return value;
      }
    }
    return '';
  };
  const result = window.__jtSessionProbe;
  if (result && result.state !== 'pending') return JSON.stringify(result);
  const publicInfo = window.WIS_PUBLIC_INFO;
  if (publicInfo && typeof publicInfo === 'object') {
    const loginUserId = text(publicInfo.loginUserId);
    return JSON.stringify({
      state: 'complete',
      authenticated: loginUserId !== '' && loginUserId !== 'fail_user',
      loginUserId,
      studentNumber: studentNumber(publicInfo),
      studentName: studentName(publicInfo),
      loginType: text(publicInfo.loginType),
    });
  }
  if (!result) {
    window.__jtSessionProbe = {state: 'pending'};
    const url = '/yjsxkapp/sys/xsxkapp/xsxkHome/loadPublicInfo_index.do?_=' +
      Date.now();
    fetch(url, {credentials: 'include', cache: 'no-store'})
      .then(async response => {
        const body = await response.text();
        if (!response.ok) throw new Error('HTTP ' + response.status);
        let data;
        try { data = JSON.parse(body); }
        catch (_) { throw new Error('non-json-response'); }
        const loginUserId = text(data?.loginUserId);
        window.WIS_PUBLIC_INFO = data;
        window.__jtSessionProbe = {
          state: 'complete',
          authenticated: loginUserId !== '' && loginUserId !== 'fail_user',
          loginUserId,
          studentNumber: studentNumber(data),
          studentName: studentName(data),
          loginType: text(data?.loginType),
        };
      })
      .catch(error => {
        window.__jtSessionProbe = {
          state: 'error',
          authenticated: false,
          error: text(error?.message || error),
        };
      });
  }
  return JSON.stringify(window.__jtSessionProbe);
})()
""";

// Starts the official timetable request after a verified portal login. The
// response is also placed in the existing in-memory capture queue so the
// normal JSON/DOM extractor remains the single parsing path.
const portalStartTimetableFetchScript = r"""
(() => {
  if (window.__jtTimetableRequest?.state === 'pending') return 'pending';
  window.__jtTimetableRequest = {state: 'pending'};
  const url = '/yjsxkapp/sys/xsxkapp/xsxkCourse/loadKbxx.do?_=' + Date.now();
  fetch(url, {
    credentials: 'include',
    cache: 'no-store',
    headers: {'Accept': 'application/json'},
  }).then(async response => {
    const body = await response.text();
    const finalUrl = String(response.url || url);
    const contentType = String(response.headers.get('content-type') || '');
    if (!response.ok) {
      window.__jtTimetableRequest = {
        state: 'error', status: response.status,
        error: 'HTTP ' + response.status,
        finalUrl, contentType, summary: body.slice(0, 180),
      };
      return;
    }
    let data;
    try { data = JSON.parse(body); }
    catch (_) {
      window.__jtTimetableRequest = {
        state: 'error', status: response.status,
        error: 'non-json-response', finalUrl, contentType,
        summary: body.slice(0, 180),
      };
      return;
    }
    const loginUrl = String(data?.loginURL || data?.loginUrl ||
      data?.login_url || '');
    if (loginUrl || /jaccount\.sjtu\.edu\.cn/i.test(finalUrl)) {
      window.__jtTimetableRequest = {
        state: 'auth-required', status: response.status,
        error: 'authentication-required', finalUrl,
        loginUrl: loginUrl || finalUrl,
      };
      return;
    }
    window.__jtCoursePayloads = window.__jtCoursePayloads || [];
    window.__jtCoursePayloads.push({url, data});
    const arrays = {};
    for (const [key, value] of Object.entries(data || {})) {
      if (Array.isArray(value)) arrays[key] = value.length;
    }
    window.__jtTimetableRequest = {
      state: 'complete', status: response.status,
      finalUrl, contentType, arrays,
      keys: Object.keys(data || {}).slice(0, 40),
      payloadCount: window.__jtCoursePayloads.length,
    };
  }).catch(error => {
    window.__jtTimetableRequest = {
      state: 'error', status: 0,
      error: String(error?.message || error),
    };
  });
  return 'started';
})()
""";

const portalTimetableFetchResultScript = r"""
JSON.stringify(window.__jtTimetableRequest || {state: 'idle'})
""";

// Opens the timetable view without depending on one fixed portal release.
// Exact, short labels win so a surrounding navigation container is not
// clicked before its actual menu item.
const portalOpenTimetableScript = r"""
(() => {
  const visible = element => !!element &&
    (element.offsetWidth || element.offsetHeight ||
     element.getClientRects().length);
  const text = element => (element.innerText || element.textContent || '')
    .replace(/\s+/g, ' ').trim();
  const body = document.body?.innerText || '';
  if (/星期一|周一/.test(body) && /节次|上课时间/.test(body)) {
    return 'already-visible';
  }
  const exact = /^(我的课表|个人课表|课程表|课表查询|教学安排)$/;
  const partial = /(我的课表|个人课表|课程表|课表查询|教学安排)/;
  const candidates = [...document.querySelectorAll(
    'a,button,[role=button],[role=menuitem],li')]
    .filter(visible)
    .map(element => ({element, label: text(element)}))
    .filter(item => item.label && partial.test(item.label))
    .sort((a, b) => {
      const exactScore = Number(exact.test(b.label)) - Number(exact.test(a.label));
      return exactScore || a.label.length - b.label.length;
    });
  const selected = candidates[0];
  if (!selected) return 'not-found';
  selected.element.click();
  return 'clicked';
})()
""";

// The authenticated 我的计划 page loads this JSON endpoint with GET and no
// parameters. Its XSXX object renders XM, XH and YXDM_DISPLAY in #xsxxContainer.
// Fetch it in the existing portal WebView; never navigate to the plan page.
const portalStudentProfileRequestScript = r"""
(() => {
  const endpoint = '/yjsxkapp/sys/wdpyjhapp/modules/wdpyjh/wdxx.do';
  const requestId = '__PROFILE_REQUEST_ID__';
  const report = value => PortalProfile.postMessage(JSON.stringify({
    ...value, requestId
  }));
  const diagnostics = {stage: 'request', status: 0, responseType: '', fields: []};
  fetch(endpoint, {method: 'GET', credentials: 'same-origin', cache: 'no-store',
    headers: {'Accept': 'application/json, text/javascript, */*; q=0.01',
      'X-Requested-With': 'XMLHttpRequest'}})
    .then(async response => {
      diagnostics.status = response.status;
      diagnostics.responseType = response.headers.get('content-type') || '';
      if (!response.url.startsWith('https://yjsxk.sjtu.edu.cn/')) {
        diagnostics.stage = 'auth';
        return report({diagnostics});
      }
      if (response.status === 401 || response.status === 403) {
        diagnostics.stage = 'auth';
        return report({diagnostics});
      }
      if (!response.ok) {
        diagnostics.stage = 'http';
        return report({diagnostics});
      }
      if (!/json/i.test(diagnostics.responseType)) {
        diagnostics.stage = 'auth';
        return report({diagnostics});
      }
      let body;
      try {
        body = await response.json();
      } catch (_) {
        diagnostics.stage = 'parse';
        return report({diagnostics});
      }
      diagnostics.bodyType = Array.isArray(body) ? 'array' : typeof body;
      if (!body || typeof body !== 'object' || Array.isArray(body)) {
        diagnostics.stage = 'parse';
        return report({diagnostics});
      }
      diagnostics.responseKeys = Object.keys(body).slice(0, 24);
      if (!body.success) {
        diagnostics.stage = 'api';
        return report({diagnostics});
      }
      const profile = body.reMapData?.XSXX;
      if (!profile || typeof profile !== 'object' || Array.isArray(profile)) {
        diagnostics.containerKeys = body.reMapData &&
          typeof body.reMapData === 'object' ?
          Object.keys(body.reMapData).slice(0, 24) : [];
        diagnostics.stage = 'parse';
        return report({diagnostics});
      }
      diagnostics.profileKeys = Object.keys(profile).slice(0, 40);
      diagnostics.fields = ['XM', 'XH', 'YXDM_DISPLAY']
        .filter(key => Object.prototype.hasOwnProperty.call(profile, key));
      diagnostics.stage = 'complete';
      const field = key => typeof profile[key] === 'string' ||
        typeof profile[key] === 'number' ? String(profile[key]).trim() : '';
      report({studentName: field('XM'), studentNumber: field('XH'),
        studentCollege: field('YXDM_DISPLAY').replace(/^\s*\(\d+\)\s*/, ''),
        diagnostics});
    })
    .catch(() => report({diagnostics: {...diagnostics, stage: 'network'}}));
})()
""";

// Reads column/row context before normalizing text; merged cells preserve
// periods. Course containers are selected from the outside in so that name,
// teacher and room descendants never become separate courses.
const portalExtractionScript = r"""
(() => {
  const text = e => (e?.innerText || e?.textContent || '').trim();
  const clean = value => String(value ?? '').replace(/\s+/g, ' ').trim();
  const normKey = value => clean(value).toLowerCase()
    .replace(/[^a-z0-9\u4e00-\u9fff]/g, '');
  const compact = value => {
    if (value == null) return '';
    if (['string', 'number', 'boolean'].includes(typeof value)) {
      return clean(value);
    }
    if (Array.isArray(value)) {
      return value.map(compact).filter(Boolean).join('、');
    }
    if (typeof value === 'object') {
      for (const preferred of ['name', '姓名', '名称', 'xm', 'jsxm', 'jsmc',
        'teacherName', 'text', 'label', 'value', 'title']) {
        const key = Object.keys(value).find(item =>
          normKey(item) === normKey(preferred));
        if (key != null && compact(value[key])) return compact(value[key]);
      }
      return Object.values(value).map(compact).filter(Boolean).join('、');
    }
    return clean(value);
  };
  const recordValue = (record, aliases) => {
    const wanted = aliases.map(normKey);
    for (const [key, value] of Object.entries(record || {})) {
      if (wanted.includes(normKey(key)) && compact(value)) return compact(value);
    }
    const suffixAliases = new Set([
      'kcmc', 'kcm', 'kch', 'jsxm', 'jsmc', 'skjs', 'skjsxm', 'rkjs',
      'rkjsxm', 'skdd', 'jxcd', 'jxdd', 'jasmc', 'sksj', 'xq', 'xqj',
      'ksjc', 'ksjcdm', 'jsjc', 'jsjcdm', 'zcmc', 'bjdm', 'jxbid',
      'kcid', 'kcdm'
    ]);
    for (const [key, value] of Object.entries(record || {})) {
      const normalized = normKey(key);
      if (wanted.some(alias => suffixAliases.has(alias) && normalized.endsWith(alias)) &&
          compact(value)) return compact(value);
    }
    return '';
  };
  const attr = (node, names) => {
    for (const name of names) {
      const value = node?.getAttribute?.(name);
      if (value != null && clean(value)) return clean(value);
    }
    return '';
  };
  const queryText = (node, selectors) => {
    for (const selector of selectors) {
      try {
        const value = text(node?.querySelector?.(selector));
        if (value) return value;
      } catch (_) {}
    }
    return '';
  };
  const day = s => {
    const m = String(s || '').match(/(?:星期|周|礼拜)\s*([一二三四五六日天1-7])/);
    return m ? (Number(m[1]) || (m[1] === '天' ? 7 : '一二三四五六日'.indexOf(m[1]) + 1)) : 0;
  };
  const section = s => {
    const m = String(s || '').match(/(?:第\s*)?(\d{1,2})(?:\s*[-~～—–至]\s*(\d{1,2}))?\s*节/);
    return m ? [+m[1], +(m[2] || m[1])] : null;
  };
  const labelValue = (lines, re) => {
    const line = lines.find(value => re.test(value));
    return line ? clean(line.replace(/^.*?[:：]\s*/, '')) : '';
  };
  const courseNodes = cell => {
    const selectors = [
      '[data-course-id]', '[data-course-code]', '[data-kcid]', '[data-kch]',
      '[class~="course"]', '[class~="lesson"]', '[class*="course-item"]',
      '[class*="courseItem"]', '[class*="lesson-item"]',
      '[class*="lessonItem"]', '[class*="kbcontent"]'
    ].join(',');
    let found = [];
    try { found = [...cell.querySelectorAll(selectors)]; } catch (_) {}
    if (!found.length) return [cell];
    const outer = found.filter(node => !found.some(other =>
      other !== node && other.contains?.(node)));
    return outer.length ? outer : [cell];
  };
  const courseData = (node, fallbackValue) => {
    const value = text(node) || fallbackValue;
    const lines = value.split(/\n+/).map(clean).filter(Boolean);
    const pickedName = queryText(node, [
      '[data-course-name]', '[class*="course-name"]', '[class*="courseName"]',
      '[class*="kcmc"]', '[class*="title"]', '[class~="name"]'
    ]);
    const pickedTeacher = queryText(node, [
      '[data-teacher]', '[data-teacher-name]', '[data-instructor]',
      '[class*="teacher"]', '[class*="instructor"]', '[class*="jsxm"]',
      '[class*="jsmc"]'
    ]);
    const pickedLocation = queryText(node, [
      '[data-location]', '[data-room]', '[data-classroom]',
      '[class*="location"]', '[class*="classroom"]', '[class*="room"]',
      '[class*="jasmc"]', '[class*="skdd"]', '[class*="jxcd"]',
      '[class*="jxdd"]'
    ]);
    const pickedWeek = queryText(node, [
      '[data-weeks]', '[class*="week"]', '[class*="zc"]'
    ]);
    const teacherFallback = lines.find(line =>
      /(?:老师|教授|讲师|教师)/.test(line) &&
      !/(?:地点|教室|校区|周|第\s*\d+\s*节)/.test(line)) || '';
    const locationFallback = lines.find(line =>
      /(?:校区|教室|教学楼|(?:东|西|中|新)[上下中]?院|楼|室\b)/.test(line) &&
      !/(?:周|第\s*\d+\s*节)/.test(line)) || '';
    const teacher = clean(pickedTeacher ||
      labelValue(lines, /(?:授课教师|教师姓名|任课教师|教师|老师)\s*[:：]/) ||
      teacherFallback).replace(/^(?:授课教师|教师姓名|任课教师|教师|老师)\s*[:：]?\s*/, '');
    const location = clean(pickedLocation ||
      labelValue(lines, /(?:上课地点|上课教室|地点|教室)\s*[:：]/) ||
      locationFallback).replace(/^(?:上课地点|上课教室|地点|教室)\s*[:：]?\s*/, '');
    const courseCode = clean(attr(node, ['data-course-code', 'data-kch']) ||
      labelValue(lines, /(?:课程代码|课程编号|课号)\s*[:：]/));
    let sourceCourseId = clean(attr(node, ['data-course-id', 'data-id', 'data-kcid']));
    if (!sourceCourseId) {
      const href = node?.querySelector?.('a[href]')?.getAttribute?.('href') || '';
      const match = href.match(/[?&](?:courseId|course_id|kcid|id)=([^&#]+)/i);
      if (match) sourceCourseId = decodeURIComponent(match[1]);
    }
    const weekText = clean(pickedWeek || lines.filter(line =>
      /(?:\d|单|双)\s*(?:[-~～—–至、,，]\s*\d+)?\s*(?:单|双)?\s*周/.test(line)
    ).join('、'));
    const fallbackName = lines.find(line =>
      !/(?:教师|老师|任课教师|地点|教室|上课地点|课程代码|课程编号|课号)\s*[:：]/.test(line) &&
      !/(?:\d|单|双)\s*(?:[-~～—–至、,，]\s*\d+)?\s*(?:单|双)?\s*周/.test(line) &&
      !/^(?:第\s*)?\d{1,2}(?:\s*[-~～—–至]\s*\d{1,2})?\s*节$/.test(line)
    ) || '';
    return {
      name: clean(pickedName || fallbackName).replace(/^课程名称[:：]\s*/, ''),
      teacher, location, courseCode, sourceCourseId, weekText, time: value
    };
  };
  const jsonCourse = record => {
    if (!record || typeof record !== 'object' || Array.isArray(record)) return null;
    const name = recordValue(record,
      ['name', 'courseName', 'course_name', '课程名称', '课程名', 'kcmc', 'kcm']);
    const teacher = recordValue(record,
      ['teacher', 'teacherName', 'teacher_name', 'teachers', 'instructor',
       'instructors', '任课教师', '授课教师', '教师', '教师姓名', '教师名称',
       '教师列表', 'skjs', 'skjsxm', 'rkjs', 'rkjsxm', 'xm', 'jsxm',
       'jsmc']);
    const location = recordValue(record,
      ['location', 'classroom', 'room', 'building', '上课地点', '上课教室',
       '教室', '地点', '课室', '教学楼', '教室名称', 'jasmc', 'skdd',
       'jxcd', 'jxdd']);
    let time = recordValue(record,
      ['time', 'schedule', 'courseTime', 'classTime', '上课时间', '课程时间',
       '时间', '上课安排', 'sksj']);
    const weekday = recordValue(record,
      ['weekday', 'dayOfWeek', '星期', '星期几', 'xq', 'xqj']);
    const startPeriod = recordValue(record,
      ['startPeriod', '开始节次', '起始节次', 'ksjc', 'ksjcdm']);
    const endPeriod = recordValue(record,
      ['endPeriod', '结束节次', 'jsjc', 'jsjcdm']);
    const weekText = recordValue(record,
      ['weekText', 'weeks', '上课周次', '周次', 'zcmc']);
    if (!time) {
      time = [weekday, startPeriod && endPeriod
        ? '第' + startPeriod + '-' + endPeriod + '节' : '', weekText]
        .filter(Boolean).join(' ');
    }
    const courseCode = recordValue(record,
      ['courseCode', 'course_code', 'code', '课程代码', '课程编号', '课号',
       'kch', 'kcdm']);
    const sourceCourseId = recordValue(record,
      ['sourceCourseId', 'portalCourseId', 'courseId', 'course_id', '课程ID',
       '教学班ID', '教学班编号', 'bjdm', 'jxbid', 'kcid']);
    const keys = Object.keys(record).map(normKey);
    const hasMarker = keys.some(key =>
      /课程|course|kcmc|sksj|skdd|jsxm|jasmc|jxcd|bjdm|jxb/.test(key));
    const useful = [name, teacher, location, time, courseCode].filter(Boolean).length;
    if (!name || (!hasMarker && useful < 2)) return null;
    return {name, teacher, location, time, weekday, startPeriod, endPeriod,
      weekText, courseCode, sourceCourseId};
  };
  const lessonCourses = record => {
    if (!record || typeof record !== 'object' || Array.isArray(record)) return [];
    const nestedCourse = record.course && typeof record.course === 'object' &&
      !Array.isArray(record.course) ? record.course : null;
    const classes = Array.isArray(record.classes) ? record.classes : [];
    const hasLessonShape = nestedCourse &&
      (classes.length || record.teachers || record.kind === 'sjtu.lesson');
    if (!hasLessonShape) return [];

    const name = recordValue(nestedCourse,
      ['name', 'courseName', 'course_name', '课程名称', '课程名', 'kcmc']);
    if (!name) return [];
    const teacher = recordValue(record,
      ['teachers', 'teacher', 'teacherName', 'instructors', '任课教师',
       '授课教师', '教师', '教师姓名', 'skjs', 'skjsxm', 'rkjs', 'rkjsxm',
       'jsxm', 'jsmc']);
    const courseCode = recordValue(nestedCourse,
      ['code', 'courseCode', 'course_code', '课程代码', '课程编号', 'kch']);
    const sourceCourseId = recordValue(record,
      ['bsid', 'sourceCourseId', 'teachingClassId', 'courseId', '教学班ID',
       '教学班编号', 'jxbid', 'kcid', 'id']);
    const zeroBased = record.kind === 'sjtu.lesson';
    if (!classes.length) {
      return [{name, teacher, location: '', time: '', weekday: '',
        startPeriod: '', endPeriod: '', weekText: '', courseCode,
        sourceCourseId}];
    }
    return classes.map(item => {
      const schedule = item?.schedule && typeof item.schedule === 'object'
        ? item.schedule : item || {};
      const classroom = item?.classroom ?? item?.room ?? {};
      const dayText = recordValue(schedule,
        ['day', 'weekday', 'dayOfWeek', '星期', 'xqj']);
      const periodText = recordValue(schedule,
        ['period', 'startPeriod', '开始节次', 'ksjc']);
      const lastText = recordValue(schedule,
        ['last', 'duration', '持续节次']);
      const endText = recordValue(schedule,
        ['endPeriod', '结束节次', 'jsjc']);
      const rawDay = dayText === '' ? NaN : Number(dayText);
      const rawPeriod = periodText === '' ? NaN : Number(periodText);
      const rawLast = lastText === '' ? NaN : Number(lastText);
      const explicitEnd = endText === '' ? NaN : Number(endText);
      const scheduleZeroBased = zeroBased || schedule.kind === 'sjtu.schedule';
      const weekday = Number.isFinite(rawDay) && rawDay >= 0
        ? rawDay + (scheduleZeroBased ? 1 : 0) : '';
      const startPeriod = Number.isFinite(rawPeriod) && rawPeriod >= 0
        ? rawPeriod + (scheduleZeroBased ? 1 : 0) : '';
      const endPeriod = Number.isFinite(explicitEnd) && explicitEnd >= 0
        ? explicitEnd + (scheduleZeroBased ? 1 : 0)
        : (startPeriod && rawLast > 0 ? startPeriod + rawLast - 1 : startPeriod);
      const rawWeekText = recordValue(schedule,
        ['week', 'weeks', '周次', 'zcmc']);
      const rawWeek = rawWeekText === '' ? NaN : Number(rawWeekText);
      const weekText = Number.isFinite(rawWeek) && rawWeek >= 0
        ? String(rawWeek + (scheduleZeroBased ? 1 : 0)) + '周'
        : recordValue(schedule, ['weeks', 'weekText', '周次', 'zcmc']);
      const location = compact(classroom) || recordValue(item,
        ['location', 'classroom', 'room', '上课地点', '上课教室', 'skdd']);
      const time = [weekday ? '周' + weekday : '', startPeriod
        ? '第' + startPeriod + '-' + endPeriod + '节' : '', weekText]
        .filter(Boolean).join(' ');
      return {name, teacher, location, time, weekday, startPeriod,
        endPeriod, weekText, courseCode, sourceCourseId};
    });
  };
  const walkJson = (value, output, depth = 0) => {
    if (depth > 12 || value == null) return;
    if (Array.isArray(value)) {
      value.forEach(item => walkJson(item, output, depth + 1));
      return;
    }
    if (typeof value !== 'object') return;
    const structured = lessonCourses(value);
    if (structured.length) output.push(...structured);
    else {
      const course = jsonCourse(value);
      if (course) output.push(course);
    }
    Object.values(value).forEach(item => walkJson(item, output, depth + 1));
  };

  const result = [];
  const documents = [document];
  for (const frame of document.querySelectorAll('iframe')) {
    try { if (frame.contentDocument) documents.push(frame.contentDocument); } catch (_) {}
  }
  for (const doc of documents) {
    try {
      const payloads = doc.defaultView?.__jtCoursePayloads || [];
      for (const payload of payloads) walkJson(payload?.data, result);
    } catch (_) {}
  }
  for (const doc of documents) for (const table of doc.querySelectorAll('table')) {
    const grid = [];
    const origins = [];
    [...table.rows].forEach((row, r) => {
      grid[r] ||= [];
      let col = 0;
      for (const cell of row.cells) {
        while (grid[r][col]) col++;
        const entry = {cell, r, col, value: text(cell)};
        origins.push(entry);
        for (let y = r; y < r + cell.rowSpan; y++) {
          grid[y] ||= [];
          for (let x = col; x < col + cell.colSpan; x++) grid[y][x] = entry;
        }
        col += cell.colSpan;
      }
    });
    const headerIndex = grid.findIndex(row =>
      row.filter(entry => entry && day(entry.value) && entry.value.length < 25).length >= 3);
    if (headerIndex >= 0) {
      const header = grid[headerIndex];
      const periodAt = r => {
        const row = grid[r] || [];
        for (let c = 0; c < row.length; c++) {
          if (header[c] && day(header[c].value)) break;
          const value = row[c]?.value || '';
          const found = section(value);
          if (found) return found;
          if (/^\d{1,2}$/.test(value)) return [+value, +value];
        }
        return null;
      };
      for (const entry of origins) {
        const weekday = day(header[entry.col]?.value || '');
        if (!weekday || entry.r <= headerIndex || !entry.value) continue;
        const start = periodAt(entry.r);
        const end = periodAt(entry.r + entry.cell.rowSpan - 1);
        for (const node of courseNodes(entry.cell)) {
          const value = text(node);
          if (!value || /^(无|暂无|[-—])$/.test(value)) continue;
          const data = courseData(node, entry.value);
          if (!data.name && !data.courseCode && !data.sourceCourseId) continue;
          result.push({...data, weekday,
            startPeriod: start?.[0], endPeriod: end?.[1] || start?.[1]});
        }
      }
    } else {
      const hi = grid.findIndex(row => row.some(entry =>
        /^(课程名称|课程名)$/.test(entry?.value || '')));
      if (hi < 0) continue;
      const headers = grid[hi].map(entry => entry?.value || '');
      const find = re => headers.findIndex(value => re.test(value));
      const ni = find(/^课程名/), ti = find(/上课时间|时间安排|教学安排/);
      const di = find(/星期|周几/), pi = find(/节次/);
      const li = find(/地点|教室/), ji = find(/教师|老师/);
      const wi = find(/上课周次|^周次$/), ci = find(/课程代码|课程编号|课号/);
      const ii = find(/课程ID|教学班ID|课程序号/);
      for (let r = hi + 1; r < grid.length; r++) {
        const values = grid[r].map(entry => entry?.value || '');
        const name = values[ni] || '';
        if (!name || name === headers[ni]) continue;
        const schedule = [values[ti], values[di], values[pi]].filter(Boolean).join(' ');
        const parts = schedule.split(/(?=(?:星期|周|礼拜)[一二三四五六日天1-7])/).filter(Boolean);
        const meetings = parts.filter(value => day(value));
        for (const time of meetings.length ? meetings : [schedule]) {
          result.push({name, time, weekday: day(time),
            weekText: values[wi] || time, courseCode: values[ci] || '',
            sourceCourseId: values[ii] || '', location: values[li] || '',
            teacher: values[ji] || ''});
        }
      }
    }
  }
  const seen = new Set();
  return JSON.stringify(result.filter(course => {
    const key = [course.sourceCourseId || course.courseCode || course.name,
      course.weekday, course.startPeriod, course.endPeriod, course.weekText,
      course.teacher, course.location].join('|');
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  }));
})()
""";
