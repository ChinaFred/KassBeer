import assert from "node:assert/strict";
import { describe, it } from "node:test";

import {
  EMAIL_REPLACEMENT,
  cleanMultiline,
  neutralizeIssueReferences,
  neutralizeMarkup,
  neutralizeMentions,
  publicText,
  singleLine,
  storedReplyText,
} from "../src/tickets/text";

const ZWSP = "\u200b";

describe("publicText — adresses e-mail (P24)", () => {
  const cases: Record<string, string> = {
    "adresse simple": "Écrivez à jean@exemple.fr merci",
    "arobase pleine chasse": "Écrivez à jean＠exemple．fr merci",
    "espace sans chasse dans l'adresse": `Écrivez à jean${ZWSP}@exemple.fr merci`,
    "commentaire HTML dans l'adresse": "Écrivez à jean<!-- x -->@exemple.fr merci",
    "commentaire HTML pleine chasse": "Écrivez à jean＜!-- x --＞@exemple.fr merci",
    "trait d'union conditionnel": "Écrivez à je\u00adan@exemple.fr merci",
  };
  for (const [name, input] of Object.entries(cases)) {
    it(`${name} : remplacée`, () => {
      const out = publicText(input);
      assert.ok(out.includes(EMAIL_REPLACEMENT), out);
      assert.ok(!/exemple/.test(out), out);
    });
  }

  it("une mention n'est pas une adresse", () => {
    assert.ok(!publicText("merci @quelquun").includes(EMAIL_REPLACEMENT));
  });
});

describe("publicText — mentions, renvois, balisage", () => {
  it("mention neutralisée", () => {
    assert.equal(neutralizeMentions("@quelquun"), `@${ZWSP}quelquun`);
    assert.ok(publicText("voir @org/team").includes(`@${ZWSP}org`));
  });

  it("renvoi #12 et owner/repo#12 neutralisés, titre Markdown gardé", () => {
    assert.equal(neutralizeIssueReferences("voir #12"), `voir #${ZWSP}12`);
    assert.equal(neutralizeIssueReferences("a/b#3"), `a/b#${ZWSP}3`);
    assert.equal(neutralizeIssueReferences("### Titre"), "### Titre");
  });

  it("GH-12 neutralisé, sans tenir compte de la casse", () => {
    assert.equal(neutralizeIssueReferences("voir GH-12"), `voir GH${ZWSP}-12`);
    assert.equal(neutralizeIssueReferences("voir gh-7"), `voir gh${ZWSP}-7`);
    assert.equal(neutralizeIssueReferences("NIGH-12"), "NIGH-12");
  });

  it("adresses d'Issue et de PR coupées, avec ou sans schéma", () => {
    assert.equal(
      neutralizeIssueReferences("https://github.com/ChinaFred/KassBeer/issues/3"),
      `https://${ZWSP}github${ZWSP}.com/ChinaFred/KassBeer/issues/3`,
    );
    assert.equal(
      neutralizeIssueReferences("voir github.com/autre/depot/pull/9"),
      `voir github${ZWSP}.com/autre/depot/pull/9`,
    );
    assert.equal(
      neutralizeIssueReferences("http://www.github.com/a/b/issues/1"),
      `http://${ZWSP}www.github${ZWSP}.com/a/b/issues/1`,
    );
    assert.equal(neutralizeIssueReferences("https://github.com/a/b"), "https://github.com/a/b");
    assert.ok(publicText("https://github.com/a/b/pull/2").includes(`github${ZWSP}.com`));
  });

  it("HTML brut, image, définition de référence, pièce jointe", () => {
    const out = neutralizeMarkup(
      '<img src="x"> ![chat](https://x/y.png) [x]: https://a\nhttps://github.com/user-attachments/assets/1',
    );
    assert.ok(out.includes(`<${ZWSP}img`));
    assert.ok(out.includes(`!${ZWSP}[chat]`));
    assert.ok(out.includes(`]${ZWSP}:`));
    assert.ok(out.includes(`https://${ZWSP}github.com/user-attachments`));
  });

  it("commentaire HTML retiré, ouverture sans fermeture retirée", () => {
    assert.equal(publicText("a<!-- caché -->b"), "ab");
    assert.equal(publicText("a<!-- tout le reste"), "a tout le reste");
  });

  it("caractères de contrôle retirés, retours à la ligne gardés", () => {
    assert.equal(cleanMultiline("a\u0007b\r\nc\td"), "ab\nc\td");
  });

  it("singleLine ramène les blancs à une espace", () => {
    assert.equal(singleLine("  a \n\t b  "), "a b");
  });
});

describe("storedReplyText", () => {
  it("adresse remplacée, balisage gardé (texte simple dans l'application)", () => {
    assert.equal(
      storedReplyText("Merci <b>jean@exemple.fr</b>", 100),
      `Merci <b>${EMAIL_REPLACEMENT}</b>`,
    );
  });

  it("borné, terminé par une ellipse", () => {
    const out = storedReplyText("x".repeat(50), 10);
    assert.equal(Array.from(out).length, 10);
    assert.ok(out.endsWith("…"));
  });
});

describe("publicText — contrôles bidirectionnels (P24)", () => {
  it("U+202E retiré : « a\u202Eb » rend « ab »", () => assert.equal(publicText("a\u202Eb"), "ab"));
  it("U+200E, U+200F, U+202A à U+202E, U+2066 à U+2069 retirés", () => {
    const bidi = [
      0x200e, 0x200f, 0x202a, 0x202b, 0x202c, 0x202d, 0x202e, 0x2066, 0x2067, 0x2068, 0x2069,
    ];
    for (const code of bidi) {
      assert.equal(publicText(`a${String.fromCharCode(code)}b`), "ab", code.toString(16));
    }
  });
});
