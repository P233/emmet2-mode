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
Deno.test(".", () => assertEquals(expandJSX("."), "<div className={}>|</div>"));
Deno.test(".class", () => assertEquals(expandJSX(".class"), "<div className={css.class}>|</div>"));
Deno.test("ABC.XYZ", () => assertEquals(expandJSX("ABC.XYZ"), "<ABC.XYZ>|</ABC.XYZ>"));
Deno.test("ABC.XYZ/", () => assertEquals(expandJSX("ABC.XYZ/"), "<ABC.XYZ />"));
Deno.test("Abc.Xyz/", () => assertEquals(expandJSX("Abc.Xyz/"), "<Abc.Xyz />"));
Deno.test("ABC.XYZ.class", () => assertEquals(expandJSX("ABC.XYZ.class"), "<ABC.XYZ className={css.class}>|</ABC.XYZ>"));
Deno.test("ABC.XYZ.class/", () => assertEquals(expandJSX("ABC.XYZ.class/"), "<ABC.XYZ className={css.class} />"));
Deno.test("ABC.XYZ.a.b.c/", () => assertEquals(expandJSX("ABC.XYZ.a.b.c/"), "<ABC.XYZ className={clsx(css.a, css.b, css.c)} />"));
Deno.test("ABC./", () => assertEquals(expandJSX("ABC./"), "<ABC className={|} />"));

// Solid
Deno.test(".", () => assertEquals(expandJSX(".", { classAttr: true }), "<div class={}>|</div>"));
Deno.test(".class", () => assertEquals(expandJSX(".class", { classAttr: true }), "<div class={css.class}>|</div>"));
Deno.test(".a.b.c", () => assertEquals(expandJSX(".a.b.c", { classAttr: true }), "<div class={clsx(css.a, css.b, css.c)}>|</div>"));
