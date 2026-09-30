const canvasUrl = 'https://oc.sjtu.edu.cn/login/canvas';
const canvasSsoUrl = 'https://oc.sjtu.edu.cn/login/openid_connect';

Uri get canvasExtractionScriptUri =>
    Uri.parse('javascript:${Uri.encodeComponent(canvasExtractionScript)}');

// Sends the catalog before the large rosters so Flutter can match courses
// immediately. Messages remain chunked for Android's JavaScript bridge.
const canvasExtractionScript = r'''
(() => {
  const send = value => SyncBridge.postMessage(JSON.stringify(value));
  const value = (input, fallback = '') => input == null ? fallback : String(input);
  const wait = ms => new Promise(resolve => setTimeout(resolve, ms));
  const nextLink = header => {
    if (!header) return null;
    for (const part of header.split(',')) {
      if (/rel="next"/.test(part)) return part.match(/<([^>]+)>/)?.[1] || null;
    }
    return null;
  };
  const failure = (message, endpoint = '', status = 0, body = '') => {
    const error = new Error(message);
    error.endpoint = endpoint; error.status = status; error.body = body;
    return error;
  };
  const detail = error => {
    const status = error?.status ? 'HTTP ' + error.status + ' ' : '';
    return status + value(error?.message || error, '未知错误');
  };
  const fetchText = async (url, attempts) => {
    let lastError;
    for (let attempt = 0; attempt < attempts; attempt++) {
      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), 15000);
      try {
        const response = await fetch(url, {credentials: 'include',
          headers: {'Accept': 'application/json'}, signal: controller.signal});
        const body = await response.text();
        if (!response.ok) throw failure(response.statusText || '请求失败',
          url, response.status, body);
        return {response, body};
      } catch (error) {
        lastError = error?.name === 'AbortError'
          ? failure('请求超时', url) : error;
        if (attempt + 1 < attempts) await wait([1200, 3000, 6000][attempt]);
      } finally { clearTimeout(timeout); }
    }
    throw lastError || failure('请求失败', url);
  };
  const allPages = async (initialUrl, attempts = 2, onPage) => {
    const rows = []; let url = initialUrl;
    while (url) {
      const result = await fetchText(url, attempts); let data;
      try { data = result.body ? JSON.parse(result.body) : []; }
      catch (_) { throw failure('接口返回的不是有效 JSON', url,
        result.response.status, result.body); }
      if (!Array.isArray(data)) {
        const message = data && typeof data === 'object'
          ? value(data.message || data.error || data.errors) : '';
        throw failure(message || '接口返回结构不是数组', url,
          result.response.status, result.body);
      }
      if (onPage) onPage({endpoint: url, status: result.response.status,
        returnedCount: data.length});
      rows.push(...data.filter(item => item && typeof item === 'object'));
      url = nextLink(result.response.headers.get('Link'));
    }
    return rows;
  };
  const chunks = (items, size) => {
    const result = [];
    for (let i = 0; i < items.length; i += size) result.push(items.slice(i, i + size));
    return result;
  };
  const compactItem = (item, courseName = '', courseId = '', fallbackType = '通知') => ({
    id: value(item?.id ?? item?.asset_id),
    assetId: value(item?.asset_id ?? (fallbackType === '公告' ? item?.id : '')),
    assetType: value(item?.asset_type),
    contextType: value(item?.context_type),
    courseId: value(courseId || item?.course_id ||
      (String(item?.context_type || '').toLowerCase() === 'course'
        ? item?.context_id : '')),
    title: value(item?.title ?? item?.subject ?? item?.message, 'Canvas 通知'),
    messageHtml: value(item?.message ?? item?.summary),
    type: value(item?.type ?? item?.activity_type, fallbackType),
    courseName: value(courseName || item?.context_name || item?.course_name),
    createdAt: value(item?.created_at ?? item?.posted_at ?? item?.updated_at),
    htmlUrl: value(item?.html_url ?? item?.url)
  });
  const announcementIdentity = item => {
    const id = value(item?.id ?? item?.asset_id);
    if (id) return 'id:' + id;
    const url = value(item?.html_url ?? item?.url);
    const topic = url.match(/\/(?:discussion_topics|announcements)\/(\d+)(?:[/?#]|$)/i);
    if (topic) return 'url:' + topic[1];
    const title = value(item?.title ?? item?.subject).toLowerCase()
      .replace(/<[^>]*>/g, '').replace(/\s+/g, ' ').trim();
    const date = value(item?.posted_at ?? item?.created_at ?? item?.updated_at);
    const message = value(item?.message).replace(/\s+/g, ' ').trim();
    return title || date || message ? 'content:' + title + ':' + date + ':' + message : '';
  };
  const parseAnnouncements = (rows, courseName, courseId) => {
    const byIdentity = new Map();
    let parsedCount = 0;
    for (const raw of rows) {
      if (!raw || typeof raw !== 'object' || Array.isArray(raw)) continue;
      const title = value(raw.title ?? raw.subject);
      const id = value(raw.id ?? raw.asset_id);
      if (!title && !id) continue;
      const item = compactItem(raw, courseName, courseId, '公告');
      item.courseId = courseId;
      item.courseName = courseName;
      const identity = announcementIdentity(raw) ||
        'parsed:' + courseId + ':' + parsedCount;
      const previous = byIdentity.get(identity);
      if (!previous) {
        byIdentity.set(identity, item);
        parsedCount++;
      } else {
        if (item.messageHtml.length > previous.messageHtml.length) {
          previous.messageHtml = item.messageHtml;
        }
        if (!previous.htmlUrl) previous.htmlUrl = item.htmlUrl;
        if (!previous.createdAt) previous.createdAt = item.createdAt;
      }
    }
    return [...byIdentity.values()];
  };
  const readCourseAnnouncements = async (endpoint, course) => {
    const pageStatuses = [];
    let returnedCount = 0;
    try {
      const rows = await allPages(endpoint, 2, page => {
        pageStatuses.push(page.status);
        returnedCount += page.returnedCount;
      });
      const items = parseAnnouncements(rows,
        value(course?.name, '未命名 Canvas 课程'), value(course?.id));
      const parseSkipped = Math.max(0, returnedCount - items.length);
      send({kind: 'diagnostic',
        stage: parseSkipped > 0 ? 'announcement_parse_partial' : 'announcement_read',
        courseName: value(course?.name, '未命名 Canvas 课程'),
        courseId: value(course?.id), endpoint,
        httpStatus: pageStatuses.join('/'), returnedCount,
        parsedCount: items.length,
        error: parseSkipped > 0 ? '存在无法识别的公告记录，已跳过' : ''});
      return {items, error: '', httpStatus: pageStatuses.join('/'),
        returnedCount, parsedCount: items.length};
    } catch (error) {
      const status = error?.status || 0;
      if (status && pageStatuses.length === 0) pageStatuses.push(status);
      const message = detail(error);
      const parseFailure = /不是有效 JSON|结构不是数组/.test(message);
      send({kind: 'diagnostic',
        stage: parseFailure ? 'announcement_parse' : 'announcement_request',
        courseName: value(course?.name, '未命名 Canvas 课程'),
        courseId: value(course?.id), endpoint,
        httpStatus: pageStatuses.join('/') || String(status),
        returnedCount, parsedCount: 0, error: message});
      return {items: [], error: message,
        httpStatus: pageStatuses.join('/') || String(status),
        returnedCount, parsedCount: 0};
    }
  };
  const compactPerson = person => ({
    id: value(person?.id), name: value(person?.name ?? person?.short_name, '未命名成员'),
    email: value(person?.email), loginId: value(person?.login_id),
    avatarUrl: value(person?.avatar_url ?? person?.avatar_image_url ??
      person?.avatar?.url ?? person?.avatar),
    enrollments: Array.isArray(person?.enrollments)
      ? person.enrollments.filter(item => item && typeof item === 'object')
          .map(item => ({role: value(item.role), type: value(item.type)})) : []
  });
  const runLimited = async (items, limit, task) => {
    let cursor = 0;
    const workers = Array.from({length: Math.min(limit, items.length)}, async () => {
      while (cursor < items.length) { const index = cursor++; await task(items[index]); }
    });
    await Promise.all(workers);
  };
  const sendCourse = (course, errors = {}) => send({kind: 'course', data: {
    id: value(course?.id), name: value(course?.name, '未命名 Canvas 课程'),
    courseCode: value(course?.course_code), sisCourseId: value(course?.sis_course_id),
    integrationId: value(course?.integration_id),
    syllabusHtml: value(course?.syllabus_body), errors
  }});

  (async () => {
    send({kind: 'start'});
    send({kind: 'progress', stage: 'connecting', message: '正在连接 Canvas'});
    try {
      // Do not filter the catalog to the Canvas "available" state: some
      // current student enrollments are active but not marked available.
      const courses = await allPages('/api/v1/courses?' +
        'include[]=syllabus_body&include[]=term&per_page=100', 3);
      courses.filter(course => value(course?.id)).forEach(course => sendCourse(course));
      send({kind: 'progress', stage: 'matching', message: '正在匹配课程'});
      send({kind: 'catalogComplete'});

      // Dashboard and per-course details are independent. Do not make one
      // slow activity stream block all announcements and rosters.
      const dashboardTask = (async () => {
        let dashboard = [], dashboardError = '';
        try {
          dashboard = (await allPages('/api/v1/users/self/activity_stream?per_page=100'))
            .map(item => compactItem(item));
        } catch (error) {
          dashboardError = detail(error);
          send({kind: 'diagnostic', stage: '控制面板通知',
            endpoint: value(error?.endpoint), error: dashboardError});
        }
        const dashboardChunks = chunks(dashboard, 25);
        if (!dashboardChunks.length) send({kind: 'dashboard', items: [], error: dashboardError});
        else dashboardChunks.forEach((items, index) => send({kind: 'dashboard', items,
          error: index === 0 ? dashboardError : '', append: index > 0}));
      })();

      let completed = 0;
      send({kind: 'progress', stage: 'details', completed: 0,
        total: courses.length, message: '正在同步课程内容'});
      await runLimited(courses, 3, async course => {
        const id = value(course?.id); if (!id) return;
        const name = value(course?.name, '未命名 Canvas 课程');
        const errors = {}; let announcements = [], people = [];
        await Promise.all([
          (async () => {
            const directEndpoint = '/api/v1/courses/' + encodeURIComponent(id) +
              '/discussion_topics?only_announcements=true&per_page=100';
            const params = new URLSearchParams();
            params.set('context_codes[]', 'course_' + id);
            params.set('per_page', '100');
            // The global announcements endpoint otherwise defaults to a
            // limited date window. Explicit bounds keep older course notices.
            params.set('start_date', '1970-01-01T00:00:00Z');
            params.set('end_date', '2100-01-01T00:00:00Z');
            params.set('latest_only', 'false');
            const contextEndpoint = '/api/v1/announcements?' + params.toString();
            // Read through both Canvas-supported course announcement paths.
            // This covers account instances where one endpoint omits a course
            // announcement, while keeping all requests scoped to this course.
            const [direct, context] = await Promise.all([
              readCourseAnnouncements(directEndpoint, course),
              readCourseAnnouncements(contextEndpoint, course),
            ]);
            const unique = new Map();
            for (const item of [...direct.items, ...context.items]) {
              const identity = announcementIdentity(item) ||
                'fallback:' + item.title + ':' + item.createdAt;
              const previous = unique.get(identity);
              if (!previous) unique.set(identity, item);
              else {
                if (item.messageHtml.length > previous.messageHtml.length) {
                  previous.messageHtml = item.messageHtml;
                }
                if (!previous.htmlUrl) previous.htmlUrl = item.htmlUrl;
                if (!previous.createdAt) previous.createdAt = item.createdAt;
              }
            }
            announcements = [...unique.values()];
            if (direct.error && context.error) {
              errors.announcements =
                'course endpoint: ' + direct.error + '; context endpoint: ' + context.error;
            }
            if (announcements.length === 0) {
              const returnedCount = direct.returnedCount + context.returnedCount;
              send({kind: 'diagnostic', stage: 'announcement_empty',
                courseName: name, courseId: id,
                endpoint: directEndpoint + ' | ' + contextEndpoint,
                httpStatus: direct.httpStatus + ' | ' + context.httpStatus,
                returnedCount, parsedCount: direct.parsedCount + context.parsedCount,
                error: errors.announcements ||
                  (returnedCount > 0 ? '接口有返回但公告记录解析失败' : '两个接口均未返回公告')});
            }
          })(),
          (async () => {
            try {
              people = (await allPages('/api/v1/courses/' + encodeURIComponent(id) +
                '/users?include[]=enrollments&include[]=avatar_url&per_page=100'))
                .map(compactPerson);
            } catch (error) {
              errors.people = detail(error);
              send({kind: 'diagnostic', stage: '班级成员', courseId: id,
                endpoint: value(error?.endpoint), error: errors.people});
            }
          })()
        ]);
        sendCourse(course, errors);
        chunks(announcements, 10).forEach(items =>
          send({kind: 'announcements', courseId: id, items}));
        chunks(people, 50).forEach(items => send({kind: 'people', courseId: id, items}));
        completed++;
        send({kind: 'progress', stage: 'details', completed, total: courses.length,
          message: '正在同步课程内容'});
      });
      await dashboardTask;
      send({kind: 'complete', syncedAt: new Date().toISOString()});
    } catch (error) {
      send({kind: 'fatal', stage: 'Canvas 课程列表', endpoint: value(error?.endpoint),
        status: error?.status || 0, error: detail(error)});
    }
  })();
})()
''';
