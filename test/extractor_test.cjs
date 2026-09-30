const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const canvasSource = fs.readFileSync('lib/services/canvas_extractor.dart', 'utf8')
  .split("const canvasExtractionScript = r'''")[1].split("''';")[0];
new vm.Script(canvasSource);
assert.match(canvasSource, /const dashboardTask =/);
assert.match(canvasSource, /await Promise\.all\(/);
const extractorFile = fs.readFileSync('lib/services/portal_extractor.dart', 'utf8');
assert.match(extractorFile, /loadPublicInfo_index\.do/);
assert.match(extractorFile, /loadKbxx\.do/);
assert.match(extractorFile, /loginUserId/);
const probeSource = extractorFile
  .split('const portalSessionProbeScript = r"""')[1].split('""";')[0];
function probe(info) {
  return JSON.parse(vm.runInNewContext(probeSource, {
    window: {WIS_PUBLIC_INFO: info},
  }));
}
assert.equal(probe({loginUserId: 'jaccount-name', studentInfo: {xh: '123456789012'}}).studentNumber, '123456789012');
assert.equal(probe({loginUserId: 'jaccount-name', studentInfo: {xm: '杨惠泽'}}).studentName, '杨惠泽');
assert.equal(probe({loginUserId: 'jaccount-name'}).studentNumber, '');
assert.equal(probe({loginUserId: '123456789012'}).studentNumber, '123456789012');
const studentSource = extractorFile
  .split('const portalStudentProfileRequestScript = r"""')[1]
  .split('""";')[0].replace('__PROFILE_REQUEST_ID__', 'test-request');
function planProfile(response) {
  return new Promise(resolve => {
    vm.runInNewContext(studentSource, {
      fetch: (path, options) => {
        assert.equal(path, '/yjsxkapp/sys/wdpyjhapp/modules/wdpyjh/wdxx.do');
        assert.equal(options.method, 'GET');
        assert.equal(options.credentials, 'same-origin');
        assert.equal(options.headers['X-Requested-With'], 'XMLHttpRequest');
        return Promise.resolve(response);
      },
      PortalProfile: {postMessage: message => resolve(JSON.parse(message))},
    });
  });
}
function jsonResponse(body, status = 200, contentType = 'application/json') {
  return {
    status, ok: status >= 200 && status < 300,
    url: 'https://yjsxk.sjtu.edu.cn/yjsxkapp/sys/wdpyjhapp/modules/wdpyjh/wdxx.do',
    headers: {get: () => contentType},
    json: async () => body,
  };
}
const source = extractorFile
  .split('const portalExtractionScript = r"""')[1].split('""";')[0];
const openTimetableSource = extractorFile
  .split('const portalOpenTimetableScript = r"""')[1].split('""";')[0];
function cell(text, rowSpan = 1, colSpan = 1) {
  return {innerText: text, rowSpan, colSpan, querySelectorAll: () => [], querySelector: () => null};
}
function richCourse({id, code, name, teacher, location, weeks}) {
  const fields = {
    name: {innerText: name},
    teacher: {innerText: teacher},
    location: {innerText: location},
    weeks: {innerText: weeks},
  };
  return {
    innerText: [name, teacher, location, weeks].join('\n'),
    contains: node => Object.values(fields).includes(node),
    getAttribute: key => ({
      'data-course-id': id,
      'data-course-code': code,
    })[key] || null,
    querySelector(selector) {
      if (selector.includes('course-name')) return fields.name;
      if (selector.includes('teacher')) return fields.teacher;
      if (selector.includes('location')) return fields.location;
      if (selector.includes('week')) return fields.weeks;
      return null;
    },
  };
}
function richCell(courses, rowSpan = 1) {
  return {
    innerText: courses.map(course => course.innerText).join('\n'),
    rowSpan,
    colSpan: 1,
    getAttribute: () => null,
    querySelector: () => null,
    querySelectorAll: selector =>
      selector.includes('[data-course-id]') ? courses : [],
  };
}
function parse(rows, payloads = []) {
  const table = {rows: rows.map(cells => ({cells}))};
  const document = {
    defaultView: {__jtCoursePayloads: payloads},
    querySelectorAll: selector => selector === 'table' ? [table] : [],
  };
  return JSON.parse(vm.runInNewContext(source, {document}));
}
const days = ['节次', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
const grid = parse([
  days.map(s => cell(s)),
  [cell('第1节'), cell('数学\n教师：张老师\n教室：东上院101', 2), cell('物理'), ...Array.from({length: 5}, () => cell(''))],
  [cell('第2节'), cell(''), cell(''), cell('化学'), cell(''), cell(''), cell('英语')],
]);
assert.equal(grid.length, 4);
assert.equal(grid.find(c => c.name === '数学').endPeriod, 2);
assert.equal(grid.find(c => c.name === '物理').weekday, 2);
assert.equal(grid.find(c => c.name === '化学').weekday, 4);
assert.equal(grid.find(c => c.name === '英语').weekday, 7);
assert.equal(grid.find(c => c.name === '数学').teacher, '张老师');
assert.equal(grid.find(c => c.name === '数学').location, '东上院101');
const nested = parse([
  days.map(s => cell(s)),
  [
    cell('第1节'),
    richCell([
      richCourse({id: 'p101', code: 'CS101', name: '算法设计', teacher: '李老师', location: '东上院101', weeks: '1-16周'}),
      richCourse({id: 'p102', code: 'MA201', name: '高等数学', teacher: '王老师', location: '中院201', weeks: '2-8双周'}),
    ], 2),
    ...Array.from({length: 6}, () => cell('')),
  ],
  [cell('第2节'), ...Array.from({length: 7}, () => cell(''))],
]);
assert.equal(nested.length, 2);
assert.deepEqual(nested.map(c => c.name), ['算法设计', '高等数学']);
assert.deepEqual(nested.map(c => c.sourceCourseId), ['p101', 'p102']);
assert.equal(nested[0].teacher, '李老师');
assert.equal(nested[0].location, '东上院101');
assert.equal(nested[0].endPeriod, 2);
const list = parse([
  ['课程名称', '任课教师', '上课地点', '上课时间'].map(s => cell(s)),
  ['算法', '李老师', '东上院', '周二 第3-4节；周四 第7-8节'].map(s => cell(s)),
]);
assert.equal(list.length, 2);
assert.deepEqual(list.map(c => c.weekday), [2, 4]);
assert.equal(parse([['学号', '姓名'].map(s => cell(s)), ['123', '同学'].map(s => cell(s))]).length, 0);

const clicked = [];
const menuItems = ['教学服务', '我的课表与教学安排', '我的课表'].map(label => ({
  innerText: label,
  offsetWidth: 20,
  offsetHeight: 20,
  getClientRects: () => [1],
  click: () => clicked.push(label),
}));
vm.runInNewContext(openTimetableSource, {
  document: {
    body: {innerText: '研究生选课'},
    querySelectorAll: () => menuItems,
  },
});
assert.deepEqual(clicked, ['我的课表']);
const captured = parse([
  days.map(s => cell(s)),
  [cell('第1节'), cell('知识产权法 LAW6001'), ...Array.from({length: 6}, () => cell(''))],
], [{data: {rows: [{
  KCMC: '知识产权法', KCH: 'LAW6001',
  授课教师: [{姓名: '陈老师'}],
  SKDD: {label: '东中院2-201'},
  XQJ: 1, KSJC: 1, JSJC: 2, ZCMC: '1-16周',
}]}}]);
const metadata = captured.find(c => c.courseCode === 'LAW6001' && c.teacher === '陈老师');
assert.ok(metadata);
assert.equal(metadata.location, '东中院2-201');
const currentPortalPayload = parse([], [{data: {
  xqdyt: '1',
  skjcList: [{DM: 3, MC: '第3节', KSSJ: '100000', JSSJ: '104500'}],
  results: '1',
  rqpkjgallList: [{
    KCMC: '刑事程序法(LAW6548-19000-X01)',
    KCDM: 'LAW6548', BJDM: '19000-X01',
    JSXM: '朱军，庄加园', JASMC: '新上院 N100',
    XQ: 2, KSJCDM: 3, JSJCDM: 4, ZCMC: '1-16周',
  }],
  xkjgList: [],
}}]);
assert.equal(currentPortalPayload.length, 1);
assert.equal(currentPortalPayload[0].weekday, '2');
assert.equal(currentPortalPayload[0].startPeriod, '3');
assert.equal(currentPortalPayload[0].endPeriod, '4');
assert.equal(currentPortalPayload[0].teacher, '朱军，庄加园');
assert.equal(currentPortalPayload[0].location, '新上院 N100');
assert.equal(currentPortalPayload[0].sourceCourseId, '19000-X01');
const officialLesson = parse([], [{data: {lessons: [{
  kind: 'sjtu.lesson',
  bsid: '19000',
  course: {name: '刑事程序法', code: 'LAW6548'},
  teachers: [{name: '赵老师'}],
  classes: [
    {
      schedule: {kind: 'sjtu.schedule', week: 0, day: 1, period: 2, last: 1},
      classroom: {name: '东上院101'},
    },
    {
      schedule: {kind: 'sjtu.schedule', week: 0, day: 1, period: 3, last: 1},
      classroom: {name: '东上院101'},
    },
  ],
}]}}]);
const lessonRows = officialLesson.filter(c => c.sourceCourseId === '19000');
assert.equal(lessonRows.length, 2);
assert.deepEqual(lessonRows.map(c => c.name), ['刑事程序法', '刑事程序法']);
assert.deepEqual(lessonRows.map(c => c.teacher), ['赵老师', '赵老师']);
assert.deepEqual(lessonRows.map(c => c.location), ['东上院101', '东上院101']);
assert.deepEqual(lessonRows.map(c => c.weekday), [2, 2]);
assert.deepEqual(lessonRows.map(c => c.startPeriod), [3, 4]);
assert.deepEqual(lessonRows.map(c => c.weekText), ['1周', '1周']);
assert.deepEqual(lessonRows.map(c => c.courseCode), ['LAW6548', 'LAW6548']);
Promise.all([
  planProfile(jsonResponse({success: true, reMapData: {XSXX: {
    XM: '张三', XH: '123456789012', YXDM_DISPLAY: '(190)法学院',
  }}})).then(profile => {
    assert.equal(profile.studentName, '张三');
    assert.equal(profile.studentNumber, '123456789012');
    assert.equal(profile.studentCollege, '法学院');
    assert.equal(profile.diagnostics.stage, 'complete');
    assert.deepEqual(Array.from(profile.diagnostics.fields),
      ['XM', 'XH', 'YXDM_DISPLAY']);
  }),
  planProfile(jsonResponse({success: true, reMapData: {}})).then(profile =>
    assert.equal(profile.diagnostics.stage, 'parse')),
  planProfile(jsonResponse(null, 200, 'text/html')).then(profile =>
    assert.equal(profile.diagnostics.stage, 'auth')),
  planProfile(jsonResponse(null, 403)).then(profile =>
    assert.equal(profile.diagnostics.stage, 'auth')),
]).then(() => console.log('Extractor tests passed: portal plan profile and course extraction.'));
