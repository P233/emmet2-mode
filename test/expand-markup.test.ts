import { assertEquals, assertObjectMatch } from "https://deno.land/std@0.159.0/testing/asserts.ts";
import { parseInput, expandHTML, expandJSX } from "../src/expand-markup.ts";

// Parse markup line
Deno.test("return (div", () => assertObjectMatch(parseInput("return (div"), { prefix: "return (", abbr: "div", suffix: "" }));
Deno.test("return ( div", () => assertObjectMatch(parseInput("return ( div"), { prefix: "return (", abbr: "div", suffix: "" }));
Deno.test("return ( div   ", () => assertObjectMatch(parseInput("return ( div"), { prefix: "return (", abbr: "div", suffix: "" }));
Deno.test("return (div)", () => assertObjectMatch(parseInput("return (div)"), { prefix: "return (", abbr: "div", suffix: ")" }));
Deno.test("return ( div );", () => assertObjectMatch(parseInput("return ( div );"), { prefix: "return (", abbr: "div", suffix: ");" }));
Deno.test("div", () => assertObjectMatch(parseInput("div"), { prefix: "", abbr: "div", suffix: "" }));
Deno.test("<div> div", () => assertObjectMatch(parseInput("<div> div"), { prefix: "<div>", abbr: "div", suffix: "" }));
Deno.test("div</div>", () => assertObjectMatch(parseInput("div</div>"), { prefix: "", abbr: "div", suffix: "</div>" }));
Deno.test("div </div>", () => assertObjectMatch(parseInput("div </div>"), { prefix: "", abbr: "div", suffix: "</div>" }));
Deno.test("<div>div<div>", () => assertObjectMatch(parseInput("<div>div<div>"), { prefix: "<div>", abbr: "div", suffix: "<div>" }));
Deno.test("<div> div <div>", () => assertObjectMatch(parseInput("<div> div <div>"), { prefix: "<div>", abbr: "div", suffix: "<div>" }));
Deno.test("</div>div<div>", () => assertObjectMatch(parseInput("</div>div<div>"), { prefix: "</div>", abbr: "div", suffix: "<div>" }));
Deno.test("</div> div <div>", () => assertObjectMatch(parseInput("</div> div <div>"), { prefix: "</div>", abbr: "div", suffix: "<div>" }));
Deno.test("</div> div <div>  ", () => assertObjectMatch(parseInput("</div> div <div>  "), { prefix: "</div>", abbr: "div", suffix: "<div>" }));
Deno.test("</span> </p> </div> div <div>  ", () => assertObjectMatch(parseInput("</span> </p> </div> div <div>  "), { prefix: "</span> </p> </div>", abbr: "div", suffix: "<div>" }));
Deno.test("<span/> <p /> </div> div <div>  ", () => assertObjectMatch(parseInput("<span/> <p /> </div> div <div>  "), { prefix: "<span/> <p /> </div>", abbr: "div", suffix: "<div>" }));

// HTML;
Deno.test("br", () => assertEquals(expandHTML("br"), "<br>"));
Deno.test(".", () => assertEquals(expandHTML("."), '<div class="">|</div>'));
Deno.test(".class", () => assertEquals(expandHTML(".class"), '<div class="class">|</div>'));

// JSX
const jsxOptions = { cssModulesObject: "css", classNamesConstructor: "clsx" };
Deno.test(".", () => assertEquals(expandJSX(".", jsxOptions), "<div className={}>|</div>"));
Deno.test(".class", () => assertEquals(expandJSX(".class", jsxOptions), "<div className={css.class}>|</div>"));
Deno.test("ABC.XYZ", () => assertEquals(expandJSX("ABC.XYZ", jsxOptions), "<ABC.XYZ>|</ABC.XYZ>"));
Deno.test("ABC.XYZ/", () => assertEquals(expandJSX("ABC.XYZ/", jsxOptions), "<ABC.XYZ />"));
Deno.test("Abc.Xyz/", () => assertEquals(expandJSX("Abc.Xyz/", jsxOptions), "<Abc.Xyz />"));
Deno.test("ABC.XYZ.class", () => assertEquals(expandJSX("ABC.XYZ.class", jsxOptions), "<ABC.XYZ className={css.class}>|</ABC.XYZ>"));
Deno.test("ABC.XYZ.class/", () => assertEquals(expandJSX("ABC.XYZ.class/", jsxOptions), "<ABC.XYZ className={css.class} />"));
Deno.test("ABC.XYZ.a.b.c/", () => assertEquals(expandJSX("ABC.XYZ.a.b.c/", jsxOptions), "<ABC.XYZ className={clsx(css.a, css.b, css.c)} />"));
Deno.test("ABC./", () => assertEquals(expandJSX("ABC./", jsxOptions), "<ABC className={|} />"));

// Solid
const solidOptions = { classAttr: true, cssModulesObject: "style", classNamesConstructor: "classnames" };
Deno.test(".", () => assertEquals(expandJSX(".", solidOptions), "<div class={}>|</div>"));
Deno.test(".class", () => assertEquals(expandJSX(".class", solidOptions), "<div class={style.class}>|</div>"));
Deno.test(".a.b.c", () => assertEquals(expandJSX(".a.b.c", solidOptions), "<div class={classnames(style.a, style.b, style.c)}>|</div>"));
