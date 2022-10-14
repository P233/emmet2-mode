import { assertEquals } from "https://deno.land/std@0.159.0/testing/asserts.ts";
import expandCSS from "./expand-css.ts";

// emmet default css abbreviations
Deno.test("t0", () => assertEquals(expandCSS("t0"), "top: 0;"));
Deno.test("t1", () => assertEquals(expandCSS("t1"), "top: 1px;"));
Deno.test("t1p", () => assertEquals(expandCSS("t1p"), "top: 1%;"));
Deno.test("t1!", () => assertEquals(expandCSS("t1!"), "top: 1px !important;"));
Deno.test("t$abc", () => assertEquals(expandCSS("t$abc"), "top: $abc;"));
Deno.test("t0+r0+b0+l0", () => assertEquals(expandCSS("t0+r0+b0+l0"), "top: 0;\nright: 0;\nbottom: 0;\nleft: 0;"));

// personal opinionated css abbreviations
// Deno.test("t(2)", () => assertEquals(expandCSS("t(2)"), "top: rhythm(2);"));
// Deno.test("fz16", () => assertEquals(expandCSS("fz16"), "font-size: 16px;"));
// Deno.test("fz(1)", () => assertEquals(expandCSS("fz(1)"), "font-size: ms(1);"));
// Deno.test("fz(1)!", () => assertEquals(expandCSS("fz(1)"), "font-size: ms(1) !important;"));
// Deno.test("p[$a $b 2]", () => assertEquals(expandCSS("p[$a $b 2]"), "padding: $a $b 2px;"));
// Deno.test("all0", () => assertEquals(expandCSS("all0"), "top: 0;\nright: 0;\nbottom: 0;\nleft: 0;"));
