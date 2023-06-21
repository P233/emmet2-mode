export const SELECTOR_REGEX = /^[\w.#-]*:[\w-]+(\(.+\))?(:.+)?$/;
export const SELECTOR_ELEMENTS_REGEX = /^([\w.#-]*)(:[\w-]+)?(?:(:[\w-]+)\((.+)\))?(:.+)?$/;
export const OPINIONATED_PROPERTY_REGEX = /^-?[a-z]+((\(-?\d*\.?\d+\))*|--[\w-]+|\[.+?\])!?$/;
export const OPINIONATED_ELEMENTS_REGEX = /^(-?[a-z]+)(\(.+\))?(--[\w-]+)?(\[.+?\])?(!)?/;
export const MARKUP_ABBR_REGEX = /[a-zA-Z.]+(\w*|>|-|#|:|@|\^|\$|\+|\.|\*|\/|\([^\s]+\)|\[.+?\]|\{.+\})+\s?/g;
export const CSS_IN_JS_NUMBER_REGEX = /^-?\d+\.?\d*(px)?$/;
