// https://gs.sjtu.edu.cn/post/detail/Z3MzNjY%3D
const periodStarts = [
  480,
  535,
  600,
  655,
  720,
  775,
  840,
  895,
  960,
  1015,
  1080,
  1135,
  1180
];
const periodEnds = [
  525,
  580,
  645,
  700,
  765,
  820,
  885,
  940,
  1005,
  1060,
  1125,
  1180,
  1220
];

String clockLabel(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';
