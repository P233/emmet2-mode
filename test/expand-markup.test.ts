import { assertEquals } from "https://deno.land/std@0.159.0/testing/asserts.ts";
import { expandHTML, expandJSX } from "../src/expand-markup.ts";

// HTML abbreviations
Deno.test("div", () => assertEquals(expandHTML("div"), "<div></div>"));
Deno.test(".", () => assertEquals(expandHTML("."), '<div class=""></div>'));

// JSX abbreviations
Deno.test(".class", () => assertEquals(expandJSX(".class"), "<div className={css.class}></div>"));
