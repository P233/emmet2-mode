import { assertEquals } from "https://deno.land/std@0.159.0/testing/asserts.ts";
import { expandHTML, expandJSX } from "../src/expand-markup.ts";

// HTML
Deno.test("br", () => assertEquals(expandHTML("br"), "<br>"));
Deno.test(".", () => assertEquals(expandHTML("."), '<div class=""></div>'));
Deno.test(".class", () => assertEquals(expandHTML(".class"), '<div class="class"></div>'));

// JSX
Deno.test(".", () => assertEquals(expandJSX("."), "<div className={}></div>"));
Deno.test(".class", () => assertEquals(expandJSX(".class"), "<div className={css.class}></div>"));
Deno.test("ABC.XYZ", () => assertEquals(expandJSX("ABC.XYZ"), "<ABC.XYZ></ABC.XYZ>"));
Deno.test("ABC.XYZ/", () => assertEquals(expandJSX("ABC.XYZ/"), "<ABC.XYZ />"));
Deno.test("Abc.Xyz/", () => assertEquals(expandJSX("Abc.Xyz/"), "<Abc.Xyz />"));
Deno.test("ABC.XYZ.class", () => assertEquals(expandJSX("ABC.XYZ.class"), "<ABC.XYZ className={css.class}></ABC.XYZ>"));
Deno.test("ABC.XYZ.class/", () => assertEquals(expandJSX("ABC.XYZ.class/"), "<ABC.XYZ className={css.class} />"));
Deno.test("ABC.XYZ.a.b.c/", () => assertEquals(expandJSX("ABC.XYZ.a.b.c/"), "<ABC.XYZ className={clsx(css.a, css.b, css.c)} />"));
Deno.test("ABC./", () => assertEquals(expandJSX("ABC./"), "<ABC className={} />"));

// Solid
Deno.test(".", () => assertEquals(expandJSX(".", { classAttr: true }), "<div class={}></div>"));
Deno.test(".class", () => assertEquals(expandJSX(".class", { classAttr: true }), "<div class={css.class}></div>"));
Deno.test(".a.b.c", () => assertEquals(expandJSX(".a.b.c", { classAttr: true }), "<div class={clsx(css.a, css.b, css.c)}></div>"));
