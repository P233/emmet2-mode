import { assertEquals } from "https://deno.land/std@0.159.0/testing/asserts.ts";
import expandCSS from "../src/expand-css.ts";

// Default emmet css abbreviations
Deno.test("t", () => assertEquals(expandCSS("t"), "top: |;"));
Deno.test("t0", () => assertEquals(expandCSS("t0"), "top: 0;"));
Deno.test("t1", () => assertEquals(expandCSS("t1"), "top: 1px;"));
Deno.test("t1p", () => assertEquals(expandCSS("t1p"), "top: 1%;"));
Deno.test("t1!", () => assertEquals(expandCSS("t1!"), "top: 1px !important;"));
Deno.test("t$abc", () => assertEquals(expandCSS("t$abc"), "top: $abc;"));
Deno.test("t1r", () => assertEquals(expandCSS("t1r"), "top: 1rem;"));
Deno.test("t0+r0+b0+l0", () => assertEquals(expandCSS("t0+r0+b0+l0"), "top: 0;\nright: 0;\nbottom: 0;\nleft: 0;"));
Deno.test("t-a", () => assertEquals(expandCSS("t-a"), "top: auto;"));
Deno.test("bd1#2s", () => assertEquals(expandCSS("bd1#2s"), "border: 1px #222 solid;"));
Deno.test("p1px2px3px", () => assertEquals(expandCSS("p1px2px3px"), "padding: 1px 2px 3px;"));
Deno.test("p1px2px3px!", () => assertEquals(expandCSS("p1px2px3px!"), "padding: 1px 2px 3px !important;"));
Deno.test("p$a$b$c", () => assertEquals(expandCSS("p$a$b$c"), "padding: $a $b $c;"));

// Remove default color #000
Deno.test("c", () => assertEquals(expandCSS("c"), "color: |;"));
Deno.test("bg", () => assertEquals(expandCSS("bg"), "background: |;"));

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
Deno.test("p(1)(2)(3)", () => assertEquals(expandCSS("p(1)(2)(3)"), "padding: rhythm(1) rhythm(2) rhythm(3);"));

// Opinionated custom property abbreviations
Deno.test("m--gutter", () => assertEquals(expandCSS("m--gutter"), "margin: var(--gutter);"));
Deno.test("m--gutter!", () => assertEquals(expandCSS("m--gutter!"), "margin: var(--gutter) !important;"));
Deno.test("c--primary-color", () => assertEquals(expandCSS("c--primary-color"), "color: var(--primary-color);"));
Deno.test("p--a--b--c", () => assertEquals(expandCSS("p--a--b--c"), "padding: var(--a) var(--b) var(--c);"));

// Opinionated raw property value abbreviations
Deno.test("p[1px 2px 3px]", () => assertEquals(expandCSS("p[1px 2px 3px]"), "padding: 1px 2px 3px;"));
Deno.test("p[var(--a) var(--b) var(--c)]", () => assertEquals(expandCSS("p[var(--a) var(--b) var(--c)]"), "padding: var(--a) var(--b) var(--c);"));

// Opinionated alias abbreviations
Deno.test("posa", () => assertEquals(expandCSS("posa"), "position: absolute;\nz-index: |;"));
Deno.test("posa10", () => assertEquals(expandCSS("posa10"), "position: absolute;\nz-index: 10;"));
Deno.test("posf", () => assertEquals(expandCSS("posf"), "position: fixed;\nz-index: |;"));
Deno.test("posf100", () => assertEquals(expandCSS("posf100"), "position: fixed;\nz-index: 100;"));
Deno.test("all", () => assertEquals(expandCSS("all"), "top: |;\nright: ;\nbottom: ;\nleft: ;"));
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

// Font weight alias
Deno.test("fw7", () => assertEquals(expandCSS("fw7"), "font-weight: 700;"));
Deno.test("fw700", () => assertEquals(expandCSS("fw700"), "font-weight: 700;"));

// Size alias
Deno.test("wf", () => assertEquals(expandCSS("wf"), "width: 100%;"));
Deno.test("mawf", () => assertEquals(expandCSS("mawf"), "max-width: 100%;"));
Deno.test("miwf", () => assertEquals(expandCSS("miwf"), "min-width: 100%;"));
Deno.test("hf", () => assertEquals(expandCSS("hf"), "height: 100%;"));
Deno.test("mahf", () => assertEquals(expandCSS("mahf"), "max-height: 100%;"));
Deno.test("mihf", () => assertEquals(expandCSS("mihf"), "min-height: 100%;"));

// Use "," to split abbreviations
Deno.test("t0,r0,b0,l0", () => assertEquals(expandCSS("t0,r0,b0,l0"), "top: 0;\nright: 0;\nbottom: 0;\nleft: 0;"));
Deno.test("fz(1),t(2)!", () => assertEquals(expandCSS("fz(1),t(2)!"), "font-size: ms(1);\ntop: rhythm(2) !important;"));
Deno.test("fz(1)!,lh2", () => assertEquals(expandCSS("fz(1)!,lh2"), "font-size: ms(1) !important;\nline-height: 2;"));

// Complex cases
Deno.test("posa,all0,fz(-1)!,lh(2.5)+mA,p[1px 2px 3px]!", () => assertEquals(expandCSS("posa,all0,fz(-1)!,lh(2.5)+mA,p[1px 2px 3px]!"), "position: absolute;\nz-index: |;\ntop: 0;\nright: 0;\nbottom: 0;\nleft: 0;\nfont-size: ms(-1) !important;\nline-height: rhythm(2.5);\nmargin: auto;\npadding: 1px 2px 3px !important;"));

// At ruls abbreviations
Deno.test("@ch", () => assertEquals(expandCSS("@ch"), "@charset"));
Deno.test("@co", () => assertEquals(expandCSS("@co"), "@counter-style"));
Deno.test("@f-f", () => assertEquals(expandCSS("@f-f"), "@font-face"));
Deno.test("@f-v", () => assertEquals(expandCSS("@f-v"), "@font-feature-values"));
Deno.test("@im", () => assertEquals(expandCSS("@im"), "@import"));
Deno.test("@ke", () => assertEquals(expandCSS("@ke"), "@keyframes"));
Deno.test("@la", () => assertEquals(expandCSS("@la"), "@layer"));
Deno.test("@me", () => assertEquals(expandCSS("@me"), "@media"));
Deno.test("@na", () => assertEquals(expandCSS("@na"), "@namespace"));
Deno.test("@pa", () => assertEquals(expandCSS("@pa"), "@page"));
Deno.test("@pr", () => assertEquals(expandCSS("@pr"), "@property"));
Deno.test("@us", () => assertEquals(expandCSS("@su"), "@supports"));

// Pseudo class and pseudo element abbreviations
Deno.test(":fo", () => assertEquals(expandCSS(":fo"), "&:focus {\n\t|\n}"));
Deno.test(":hov:af", () => assertEquals(expandCSS(":hov:af"), "&:hover::after {\n\t|\n}"));
Deno.test("_:fo", () => assertEquals(expandCSS("_:fo"), ":focus {\n\t|\n}"));
Deno.test(".c:fo", () => assertEquals(expandCSS(".c:fo"), ".c:focus {\n\t|\n}"));
Deno.test(".c:f-l", () => assertEquals(expandCSS(".c:f-l"), ".c::first-letter {\n\t|\n}"));
Deno.test("a.c1.c2#id:fo", () => assertEquals(expandCSS("a.c1.c2#id:fo"), "a.c1.c2#id:focus {\n\t|\n}"));
Deno.test("a.c1.c2#id:f-c", () => assertEquals(expandCSS("a.c1.c2#id:f-c"), "a.c1.c2#id:first-child {\n\t|\n}"));
Deno.test(":n(:f-c)", () => assertEquals(expandCSS(":n(:f-c)"), "&:not(:first-child) {\n\t|\n}"));
Deno.test(":n(:f-c):af", () => assertEquals(expandCSS(":n(:f-c):af"), "&:not(:first-child)::after {\n\t|\n}"));
Deno.test(":n(:f-c,:l-c)", () => assertEquals(expandCSS(":n(:f-c,:l-c)"), "&:not(:first-child):not(:last-child) {\n\t|\n}"));
Deno.test(":n(:f-c,:l-c):be", () => assertEquals(expandCSS(":n(:f-c,:l-c):be"), "&:not(:first-child):not(:last-child)::before {\n\t|\n}"));
Deno.test(":n-c(2n-1)", () => assertEquals(expandCSS(":n-c(2n-1)"), "&:nth-child(2n-1) {\n\t|\n}"));
// Deno.test(":h(+p)", () => assertEquals(expandCSS(":h(+p)"), "&:has(+ p) {\n\t|\n}"));
