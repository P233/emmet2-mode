import { assertEquals } from "https://deno.land/std@0.164.0/testing/asserts.ts";
import { getAbbr, expandHTML, expandJSX } from "../src/expand-markup.ts";

// Get Abbr and positions
Deno.test("lorem span", () => assertEquals(getAbbr("lorem span", 6), { abbr: "span", offset: 6, length: 4 }));
Deno.test("atnoeuh otnoeuh span utnehu", () => assertEquals(getAbbr("atnoeuh otnoeuh span utnehu", 20), { abbr: "span", offset: 16, length: 4 }));
Deno.test("atnoeuh otnoeuh span utnehu span", () => assertEquals(getAbbr("atnoeuh otnoeuh span utnehu span", 31), { abbr: "span", offset: 28, length: 4 }));

// HTML;
const htmlOptions = { point: 0 };
Deno.test("br", () => assertEquals(expandHTML("br", htmlOptions).snippet, "<br>"));
Deno.test(".", () => assertEquals(expandHTML(".", htmlOptions).snippet, '<div class="">|</div>'));
Deno.test(".class", () => assertEquals(expandHTML(".class", htmlOptions).snippet, '<div class="class">|</div>'));

// JSX
const jsxOptions = { cssModulesObject: "css", classConstructor: "clsx", point: 0 };
Deno.test(".", () => assertEquals(expandJSX(".", jsxOptions).snippet, "<div className={}>|</div>"));
Deno.test(".class", () => assertEquals(expandJSX(".class", jsxOptions).snippet, "<div className={css.class}>|</div>"));
Deno.test("ABC.XYZ", () => assertEquals(expandJSX("ABC.XYZ", jsxOptions).snippet, "<ABC.XYZ>|</ABC.XYZ>"));
Deno.test("ABC.XYZ/", () => assertEquals(expandJSX("ABC.XYZ/", jsxOptions).snippet, "<ABC.XYZ />"));
Deno.test("Abc.Xyz/", () => assertEquals(expandJSX("Abc.Xyz/", jsxOptions).snippet, "<Abc.Xyz />"));
Deno.test("ABC.XYZ.class", () => assertEquals(expandJSX("ABC.XYZ.class", jsxOptions).snippet, "<ABC.XYZ className={css.class}>|</ABC.XYZ>"));
Deno.test("ABC.XYZ.class/", () => assertEquals(expandJSX("ABC.XYZ.class/", jsxOptions).snippet, "<ABC.XYZ className={css.class} />"));
Deno.test("ABC.XYZ.a.b.c/", () => assertEquals(expandJSX("ABC.XYZ.a.b.c/", jsxOptions).snippet, "<ABC.XYZ className={clsx(css.a, css.b, css.c)} />"));
Deno.test("ABC./", () => assertEquals(expandJSX("ABC./", jsxOptions).snippet, "<ABC className={|} />"));

// Solid
const solidOptions = { classAttr: true, cssModulesObject: "style", classConstructor: "classnames", point: 0 };
Deno.test(".", () => assertEquals(expandJSX(".", solidOptions).snippet, "<div class={}>|</div>"));
Deno.test(".class", () => assertEquals(expandJSX(".class", solidOptions).snippet, "<div class={style.class}>|</div>"));
Deno.test(".a.b.c", () => assertEquals(expandJSX(".a.b.c", solidOptions).snippet, "<div class={classnames(style.a, style.b, style.c)}>|</div>"));
