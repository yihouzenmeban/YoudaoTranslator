declare var tjs

import Translator from './translator';

const getenv = (name: string): string => {
  if (typeof tjs.getenv === 'function') {
    return tjs.getenv(name);
  }

  return tjs.env?.[name] ?? '';
}

const main = async () => {
  const translator = new Translator(getenv('key'), getenv('secret'), getenv('platform'));

  const word: string = Array.from(tjs.args).pop() as string;

  const result = await translator.translate(word);

  console.log(result);
}

main();
