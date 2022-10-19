import { assertEquals } from "https://deno.land/std@0.159.0/testing/asserts.ts";
import expandCSS from "./expand-css.ts";

// Default emmet css abbreviations
Deno.test("t", () => assertEquals(expandCSS("t"), "top: ;"));
Deno.test("t0", () => assertEquals(expandCSS("t0"), "top: 0;"));
Deno.test("t1", () => assertEquals(expandCSS("t1"), "top: 1px;"));
Deno.test("t1p", () => assertEquals(expandCSS("t1p"), "top: 1%;"));
Deno.test("t1!", () => assertEquals(expandCSS("t1!"), "top: 1px !important;"));
Deno.test("t$abc", () => assertEquals(expandCSS("t$abc"), "top: $abc;"));
Deno.test("t1r", () => assertEquals(expandCSS("t1r"), "top: 1rem;"));
Deno.test("t0+r0+b0+l0", () => assertEquals(expandCSS("t0+r0+b0+l0"), "top: 0;\nright: 0;\nbottom: 0;\nleft: 0;"));
Deno.test("t:a", () => assertEquals(expandCSS("t:a"), "top: auto;"));
Deno.test("t-a", () => assertEquals(expandCSS("t-a"), "top: auto;"));
Deno.test("bd1#2s", () => assertEquals(expandCSS("bd1#2s"), "border: 1px #222 solid;"));
Deno.test("p1px2px3px", () => assertEquals(expandCSS("p1px2px3px"), "padding: 1px 2px 3px;"));
Deno.test("p1px2px3px!", () => assertEquals(expandCSS("p1px2px3px!"), "padding: 1px 2px 3px !important;"));
Deno.test("p$a$b$c", () => assertEquals(expandCSS("p$a$b$c"), "padding: $a $b $c;"));
Deno.test("p$a$b$c+m:a", () => assertEquals(expandCSS("p$a$b$c+m:a"), "padding: $a $b $c;\nmargin: auto;"));

// Opinionated SCSS function abbreviations
Deno.test("t(2)", () => assertEquals(expandCSS("t(2)"), "top: rhythm(2);"));
Deno.test("t(.5)", () => assertEquals(expandCSS("t(.5)"), "top: rhythm(.5);"));
Deno.test("t(0.5)", () => assertEquals(expandCSS("t(0.5)"), "top: rhythm(0.5);"));
Deno.test("t(2)!", () => assertEquals(expandCSS("t(2)!"), "top: rhythm(2) !important;"));
Deno.test("fz(1)", () => assertEquals(expandCSS("fz(1)"), "font-size: ms(1);"));
Deno.test("fz(-1)", () => assertEquals(expandCSS("fz(-1)"), "font-size: ms(-1);"));
Deno.test("fz(1)!", () => assertEquals(expandCSS("fz(1)!"), "font-size: ms(1) !important;"));
Deno.test("fz(1)+t(2)!", () => assertEquals(expandCSS("fz(1)+t(2)!"), "font-size: ms(1);\ntop: rhythm(2) !important;"));
Deno.test("fz(1)!+lh2", () => assertEquals(expandCSS("fz(1)!+lh2"), "font-size: ms(1) !important;\nline-height: 2;"));

// Opinionated custom property abbreviations
Deno.test("m--gutter", () => assertEquals(expandCSS("m--gutter"), "margin: var(--gutter);"));
Deno.test("m--gutter!", () => assertEquals(expandCSS("m--gutter!"), "margin: var(--gutter) !important;"));

// Opinionated raw property value abbreviations
Deno.test("p[1px 2px 3px]", () => assertEquals(expandCSS("p[1px 2px 3px]"), "padding: 1px 2px 3px;"));
Deno.test("p[var(--a) var(--b) var(--c)]", () => assertEquals(expandCSS("p[var(--a) var(--b) var(--c)]"), "padding: var(--a) var(--b) var(--c);"));

// Opinionated alias abbreviations
Deno.test("posa", () => assertEquals(expandCSS("posa"), "position: absolute;\nz-index: ;"));
Deno.test("posa10", () => assertEquals(expandCSS("posa10"), "position: absolute;\nz-index: 10;"));
Deno.test("posf", () => assertEquals(expandCSS("posf"), "position: fixed;\nz-index: ;"));
Deno.test("posf100", () => assertEquals(expandCSS("posf100"), "position: fixed;\nz-index: 100;"));
Deno.test("all", () => assertEquals(expandCSS("all"), "top: ;\nright: ;\nbottom: ;\nleft: ;"));
Deno.test("all0", () => assertEquals(expandCSS("all0"), "top: 0;\nright: 0;\nbottom: 0;\nleft: 0;"));
Deno.test("all8", () => assertEquals(expandCSS("all8"), "top: 8px;\nright: 8px;\nbottom: 8px;\nleft: 8px;"));
Deno.test("all8!", () => assertEquals(expandCSS("all8!"), "top: 8px !important;\nright: 8px !important;\nbottom: 8px !important;\nleft: 8px !important;"));
Deno.test("all(2)", () => assertEquals(expandCSS("all(2)"), "top: rhythm(2);\nright: rhythm(2);\nbottom: rhythm(2);\nleft: rhythm(2);"));
Deno.test("all--gutter", () => assertEquals(expandCSS("all--gutter"), "top: var(--gutter);\nright: var(--gutter);\nbottom: var(--gutter);\nleft: var(--gutter);"));
Deno.test("all$gutter", () => assertEquals(expandCSS("all$gutter"), "top: $gutter;\nright: $gutter;\nbottom: $gutter;\nleft: $gutter;"));
Deno.test("posa5+t(2)", () => assertEquals(expandCSS("posa5+t(2)"), "position: absolute;\nz-index: 5;\ntop: rhythm(2);"));

// camelCase alias, "mA" is equal to "m:a" (also "m-a")
Deno.test("mA", () => assertEquals(expandCSS("mA"), "margin: auto;"));
Deno.test("mA!", () => assertEquals(expandCSS("mA!"), "margin: auto !important;"));
Deno.test("allA", () => assertEquals(expandCSS("allA"), "top: auto;\nright: auto;\nbottom: auto;\nleft: auto;"));

// Use "," to split abbreviations
Deno.test("t0,r0,b0,l0", () => assertEquals(expandCSS("t0,r0,b0,l0"), "top: 0;\nright: 0;\nbottom: 0;\nleft: 0;"));
Deno.test("fz(1),t(2)!", () => assertEquals(expandCSS("fz(1),t(2)!"), "font-size: ms(1);\ntop: rhythm(2) !important;"));
Deno.test("fz(1)!,lh2", () => assertEquals(expandCSS("fz(1)!,lh2"), "font-size: ms(1) !important;\nline-height: 2;"));

// Complex cases
Deno.test("posa,all0,fz(-1)!,lh(2.5)+mA,p[1px 2px 3px]!", () => assertEquals(expandCSS("posa,all0,fz(-1)!,lh(2.5)+mA,p[1px 2px 3px]!"), "position: absolute;\nz-index: ;\ntop: 0;\nright: 0;\nbottom: 0;\nleft: 0;\nfont-size: ms(-1) !important;\nline-height: rhythm(2.5);\nmargin: auto;\npadding: 1px 2px 3px !important;"));

// Pseudo class and pseudo element abbreviations
// Deno.test(":fo", () => assertEquals(expandCSS(":fo"), "&:focus {\n\t\n}"));
// Deno.test("_:fo", () => assertEquals(expandCSS("_:fo"), ":focus {\n\t\n}"));
// Deno.test(".c:fo", () => assertEquals(expandCSS(".c:fo"), ".c:focus {\n\t\n}"));
// Deno.test(".c:fl", () => assertEquals(expandCSS(".c:fl"), ".c::first-letter {\n\t\n}"));
// Deno.test("a.c1.c2#id:fo", () => assertEquals(expandCSS("a.c1.c2#id:fo"), "a.c1.c2#id:focus {\n\t\n}"));
// Deno.test("a.c1.c2#id:fl", () => assertEquals(expandCSS("a.c1.c2#id:fl"), "a.c1.c2#id:first-letter {\n\t\n}"));
// Deno.test(":n(:fc)", () => assertEquals(expandCSS(":n(:fc)"), "&:not(:first-child) {\n\t\n}"));
// Deno.test(":n(:fc,:lc)", () => assertEquals(expandCSS(":n(:fc,:lc)"), "&:not(:first-child):not(:last-child) {\n\t\n}"));
// Deno.test(":h(+p)", () => assertEquals(expandCSS(":h(+p)"), "&:has(+ p) {\n\t\n}"));
