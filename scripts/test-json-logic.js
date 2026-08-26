// 单测：JSON 错误定位（V8 消息解析 + 自研状态机兜底，纯 JS）
// 与 index.html 中的实现保持一致

// 从 V8 错误消息提取位置：(line N column M) 或 position N
function parseErrPos(text, err) {
  var msg = (err && err.message) || "";
  var m = /\(line (\d+) column (\d+)\)/.exec(msg);
  if (m) return { line: +m[1], col: +m[2], message: msg };
  var p = /position (\d+)/.exec(msg);
  if (p) {
    var pos = +p[1];
    var before = text.slice(0, pos);
    return { line: before.split("\n").length, col: pos - before.lastIndexOf("\n"), message: msg };
  }
  return null;
}

// 自研轻量 JSON 语法定位器（状态机）：返回第一个错误 {line, col, reason}；合法返回 null
function jsonLocateError(text) {
  var i = 0, n = text.length, line = 1, col = 1;
  function pos() { return { line: line, col: col }; }
  function adv1() { if (i < n) { if (text[i] === "\n") { line++; col = 1; } else { col++; } i++; } }
  function advN(k) { while (k-- > 0 && i < n) adv1(); }
  function fail(reason, p) { return { line: p.line, col: p.col, reason: reason }; }
  var stack = []; // {type:'obj'|'arr', phase:'start'|'key'|'colon'|'after', justComma:bool}
  function top() { return stack[stack.length - 1]; }
  var rootState = "start"; // 顶层：start -> after

  while (i < n) {
    var c = text[i];
    if (c === " " || c === "\t" || c === "\n" || c === "\r") { adv1(); continue; }
    var ctx = top();
    var atStart = !ctx || ctx.phase === "start";
    var objKey = !!(ctx && ctx.type === "obj" && ctx.phase === "key");
    var objColon = !!(ctx && ctx.type === "obj" && ctx.phase === "colon");
    var afterVal = !!(ctx && ctx.phase === "after");

    if (atStart || objColon) {
      // —— 期待一个值（obj 的 key/value、arr 元素、顶层值）——
      if (c === '"') {
        var sp = pos(); adv1(); var closed = false;
        while (i < n) {
          var d = text[i];
          if (d === "\\") { adv1(); adv1(); continue; }
          if (d === '"') { adv1(); closed = true; break; }
          if (d === "\n") return fail("字符串含未转义换行", sp);
          adv1();
        }
        if (!closed) return fail("字符串未闭合（缺少结尾引号）", sp);
        if (ctx) {
          if (ctx.type === "obj" && ctx.phase === "start") ctx.phase = "key";
          else ctx.phase = "after";
          ctx.justComma = false;
        } else rootState = "after";
        continue;
      }
      if (c === "{" || c === "[") {
        stack.push({ type: c === "{" ? "obj" : "arr", phase: "start", justComma: false });
        adv1(); continue;
      }
      if (c === "}" || c === "]") {
        var pc = pos();
        if (!ctx) return fail("多余的 '" + c + "'", pc);
        if (ctx.phase !== "start") return fail("此处不应出现 '" + c + "'（值未完成）", pc);
        if (ctx.justComma) return fail("尾随逗号不允许", pc);
        stack.pop();
        if (top()) { top().phase = "after"; top().justComma = false; }
        else rootState = "after";
        adv1(); continue;
      }
      if (c === "," || c === ":") return fail("此处不应出现 '" + c + "'（应为值）", pos());
      // 字面量 / 数字
      var pt = pos();
      var m = /^[^\s,:\]}"']+/.exec(text.slice(i));
      var tok = m ? m[0] : c;
      advN(tok.length);
      var valid = tok === "true" || tok === "false" || tok === "null" ||
                  /^-?\d+(\.\d+)?([eE][+-]?\d+)?$/.test(tok);
      if (!valid) return fail("非法值 '" + tok + "'", pt);
      if (ctx) { ctx.phase = "after"; ctx.justComma = false; }
      else {
        if (rootState === "after") return fail("值之间缺少 ',' 或结构分隔符", pt);
        rootState = "after";
      }
      continue;
    }
    if (objKey) {
      if (c !== ":") return fail("key 后应为 ':'，实际是 '" + c + "'", pos());
      ctx.phase = "colon"; adv1(); continue;
    }
    if (afterVal) {
      if (c === ",") { ctx.phase = "start"; ctx.justComma = true; adv1(); continue; }
      if (c === "}") {
        if (ctx.type !== "obj") return fail("期望 ']' 实际 '}'", pos());
        stack.pop(); if (top()) { top().phase = "after"; top().justComma = false; } else rootState = "after";
        adv1(); continue;
      }
      if (c === "]") {
        if (ctx.type !== "arr") return fail("期望 '}' 实际 ']'", pos());
        stack.pop(); if (top()) { top().phase = "after"; top().justComma = false; } else rootState = "after";
        adv1(); continue;
      }
      return fail("此处不应出现 '" + c + "'（应为 ',' 或闭合符）", pos());
    }
    return fail("未知状态", pos());
  }
  if (stack.length) {
    var t = top();
    if (t.type === "obj" && t.phase === "key") return fail("key 后缺少 ':'", pos());
    if (t.type === "obj" && t.phase === "colon") return fail("key 后缺少值", pos());
    return fail("结构未闭合：缺少 " + stack.map(function (s) { return s.type === "obj" ? "}" : "]"; }).reverse().join(""), pos());
  }
  return null;
}

// 综合：JSON.parse + V8 消息 + 状态机兜底
function validateText(text) {
  try { JSON.parse(text); return null; } catch (e) {
    var p = parseErrPos(text, e);
    if (p) return "第 " + p.line + " 行第 " + p.col + " 列：" + p.message;
    var loc = jsonLocateError(text);
    if (loc) return "第 " + loc.line + " 行第 " + loc.col + " 列：" + loc.reason;
    return "JSON 语法错误：" + (e.message || "");
  }
}

// ---------- 测试 ----------
var cases = [
  ["合法 JSON", '{\n  "endpoint": "http://192.168.1.10:8000",\n  "token": "abc123",\n  "interval": 3\n}', "PASS_OK"],
  ["空对象", '{}', "PASS_OK"],
  ["空数组", '[]', "PASS_OK"],
  ["嵌套", '{"a": {"b": [1,2,3]}, "c": true}', "PASS_OK"],
  ["含转义字符串", '{"a": "x\\"y\\n\\t\\\\z"}', "PASS_OK"],
  ["负数/科学计数", '{"a": -1.5e3}', "PASS_OK"],
  ["尾逗号", '{\n  "a": 1,\n}', "PASS_ERR"],
  ["数组尾逗号", '[1, 2, 3,]', "PASS_ERR"],
  ["缺引号", '{\n  a: 1\n}', "PASS_ERR"],
  ["多行缺值", '{\n  "a": 1,\n  "b": \n}', "PASS_ERR"],
  ["单行缺值", '{"a": 1, "b": }', "PASS_ERR"],
  ["数组坏", '[1, 2, 3,', "PASS_ERR"],
  ["未闭合字符串", '{"a": "abc}', "PASS_ERR"],
  ["key 后无冒号", '{"a" 1}', "PASS_ERR"],
  ["括号不匹配", '{"a": [1,2}', "PASS_ERR"],
  ["多余闭合", '{"a":1}}', "PASS_ERR"],
  ["顶层多值", '1 2', "PASS_ERR"],
  ["非法值", '{"a": nope}', "PASS_ERR"],
];

var pass = 0, fail = 0;
cases.forEach(function (c) {
  var got = validateText(c[1]);
  var want = c[2];
  if (want === "PASS_OK") {
    if (got === null) { console.log("PASS  " + c[0]); pass++; }
    else { console.log("FAIL  " + c[0] + " -> " + got); fail++; }
  } else {
    if (got !== null && /第 \d+ 行第 \d+ 列/.test(got)) { console.log("PASS  " + c[0] + " -> " + got); pass++; }
    else { console.log("FAIL  " + c[0] + " -> " + got); fail++; }
  }
});
console.log("\n" + pass + " passed, " + fail + " failed");
process.exit(fail ? 1 : 0);
