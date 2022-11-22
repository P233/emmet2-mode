import { assertEquals } from "https://deno.land/std@0.164.0/testing/asserts.ts";
import { expandCSS, expandCSSinJS } from "../src/expand-css.ts";

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
Deno.test("gtc", () => assertEquals(expandCSS("gtc"), "grid-template-columns: repeat(|);"));

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
Deno.test("posa--z", () => assertEquals(expandCSS("posa--z"), "position: absolute;\nz-index: var(--z);"));
Deno.test("posa$z", () => assertEquals(expandCSS("posa$z"), "position: absolute;\nz-index: $z;"));
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

// CSS in JS
Deno.test("t", () => assertEquals(expandCSSinJS("t"), 'top: "|"'));
Deno.test("tac", () => assertEquals(expandCSSinJS("tac"), 'textAlign: "center"'));
Deno.test("all0", () => assertEquals(expandCSSinJS("all0"), "top: 0, right: 0, bottom: 0, left: 0"));
Deno.test("hf", () => assertEquals(expandCSSinJS("hf"), 'height: "100%"'));
Deno.test("fz16,lh24,tar", () => assertEquals(expandCSSinJS("fz16,lh24,tar"), 'fontSize: 16, lineHeight: 24, textAlign: "right"'));

// At ruls abbreviations
Deno.test("@ch", () => assertEquals(expandCSS("@ch"), "@charset "));
Deno.test("@co", () => assertEquals(expandCSS("@co"), "@counter-style "));
Deno.test("@fa", () => assertEquals(expandCSS("@fa"), "@font-face "));
Deno.test("@fv", () => assertEquals(expandCSS("@fv"), "@font-feature-values "));
Deno.test("@im", () => assertEquals(expandCSS("@im"), '@import "|"'));
Deno.test("@kf", () => assertEquals(expandCSS("@kf"), "@keyframes "));
Deno.test("@ly", () => assertEquals(expandCSS("@ly"), "@layer "));
Deno.test("@md", () => assertEquals(expandCSS("@md"), "@media "));
Deno.test("@ns", () => assertEquals(expandCSS("@ns"), "@namespace "));
Deno.test("@pg", () => assertEquals(expandCSS("@pg"), "@page "));
Deno.test("@pr", () => assertEquals(expandCSS("@pr"), "@property "));
Deno.test("@us", () => assertEquals(expandCSS("@su"), "@supports "));

// Pseudo class and pseudo element abbreviations
Deno.test(":fu", () => assertEquals(expandCSS(":fu"), "&:focus {\n\t|\n}"));
Deno.test(":hv:af", () => assertEquals(expandCSS(":hv:af"), "&:hover::after {\n\t|\n}"));
Deno.test("_:fu", () => assertEquals(expandCSS("_:fu"), ":focus {\n\t|\n}"));
Deno.test(".c:fu", () => assertEquals(expandCSS(".c:fu"), ".c:focus {\n\t|\n}"));
Deno.test(".c:flt", () => assertEquals(expandCSS(".c:flt"), ".c::first-letter {\n\t|\n}"));
Deno.test("a.c1.c2#id:fu", () => assertEquals(expandCSS("a.c1.c2#id:fu"), "a.c1.c2#id:focus {\n\t|\n}"));
Deno.test("a.c1.c2#id:fc", () => assertEquals(expandCSS("a.c1.c2#id:fc"), "a.c1.c2#id:first-child {\n\t|\n}"));
Deno.test(":n(:fc)", () => assertEquals(expandCSS(":n(:fc)"), "&:not(:first-child) {\n\t|\n}"));
Deno.test(":n(:fc):af", () => assertEquals(expandCSS(":n(:fc):af"), "&:not(:first-child)::after {\n\t|\n}"));
Deno.test(":n(:fc,:lc)", () => assertEquals(expandCSS(":n(:fc,:lc)"), "&:not(:first-child):not(:last-child) {\n\t|\n}"));
Deno.test(":n(:fc,:lc):be", () => assertEquals(expandCSS(":n(:fc,:lc):be"), "&:not(:first-child):not(:last-child)::before {\n\t|\n}"));
Deno.test(":nc(2n-1)", () => assertEquals(expandCSS(":nc(2n-1)"), "&:nth-child(2n-1) {\n\t|\n}"));
// Deno.test(":h(+p)", () => assertEquals(expandCSS(":h(+p)"), "&:has(+ p) {\n\t|\n}"));
