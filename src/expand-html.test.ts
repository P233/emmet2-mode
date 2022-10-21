import { assertEquals } from "https://deno.land/std@0.159.0/testing/asserts.ts";
import expandHTML from "./expand-html.ts";

// Default emmet html abbreviations
Deno.test("div", () => assertEquals(expandHTML("div"), "<div></div>"));
Deno.test(".", () => assertEquals(expandHTML("."), '<div class=\\"\\"></div>'));

Deno.test(".class", () => assertEquals(expandHTML(".class"), '<div class=\\"class\\"></div>'));
