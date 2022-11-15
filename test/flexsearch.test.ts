import Flexsearch from "npm:flexsearch";
import { assertEquals } from "https://deno.land/std@0.164.0/testing/asserts.ts";

const testIndex = new Flexsearch.Index({
  tokenize: "forward"
});

testIndex.add(0, ":active");
testIndex.add(1, "::first-letter");
testIndex.add(2, ":nth-last-child");
testIndex.add(3, "::selection");
testIndex.add(4, "::-webkit-resizer");

Deno.test(":x", () => assertEquals(testIndex.search(":x"), []));
Deno.test(":ac", () => assertEquals(testIndex.search(":ac"), [0]));
Deno.test(":f-l", () => assertEquals(testIndex.search(":f-l"), [1]));
Deno.test(":n-l-c", () => assertEquals(testIndex.search(":n-l-c"), [2]));
Deno.test(":se", () => assertEquals(testIndex.search(":se"), [3]));
Deno.test(":w-r", () => assertEquals(testIndex.search(":w-r"), [4]));
