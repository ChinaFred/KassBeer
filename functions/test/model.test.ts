import assert from "node:assert/strict";
import { describe, it } from "node:test";

import {
  buildIssueBody,
  ISSUE_SCREENSHOT_NOTE,
  buildIssueTitle,
  closingCommitFromEvents,
  closingIssueNumbers,
  creationLabels,
  lastReply,
  nextStatus,
  parisDay,
  parseTokenExpiration,
  pickDeliveredPr,
  pubspecVersionName,
  quotaRefusal,
  readCount,
  replyFromComment,
  routeTemplateOrNull,
  statusFromIssue,
  type CommentView,
  type MergedPrCandidate,
  type PublishedStatus,
} from "../src/tickets/model";

const OWNER = 16348852;
const REPO = "ChinaFred/KassBeer";

describe("corps et titre de l'Issue (P24)", () => {
  const body = buildIssueBody({
    ticketId: "abc123",
    type: "bug",
    description: "Le minuteur saute. Écrivez à jean@exemple.fr ou @quelquun, voir #12.",
    screen: "/brassins/:id/jour",
    appVersion: "0.2.0+21",
    platform: "android",
  });

  it("gabarit fixe : type, écran, version, plateforme, référence, description", () => {
    assert.match(body, /^\*\*Type :\*\* Bug$/m);
    assert.match(body, /^\*\*Écran :\*\* `\/brassins\/:id\/jour`$/m);
    assert.match(body, /^\*\*Version :\*\* `0\.2\.0\+21`$/m);
    assert.match(body, /^\*\*Plateforme :\*\* Android$/m);
    assert.match(body, /^\*\*Référence :\*\* `abc123`$/m);
    assert.match(body, /^### Description$/m);
  });

  it("phrase fixe de la capture sur chaque Issue, en dernière ligne (ADR-008, T6)", () => {
    assert.equal(ISSUE_SCREENSHOT_NOTE, "Capture éventuelle disponible dans Admin › Tickets.");
    assert.equal(body.split("\n").at(-1), ISSUE_SCREENSHOT_NOTE);
    assert.ok(!/screenshot|tickets\//.test(body));
  });

  it("description nettoyée : ni adresse, ni mention, ni renvoi actif", () => {
    assert.ok(!body.includes("exemple.fr"));
    assert.ok(body.includes("[adresse retirée]"));
    assert.ok(!/@quelquun/.test(body));
    assert.ok(!/#12/.test(body));
  });

  it("écran hors modèle : « Non précisé » ; version absente : « Version inconnue »", () => {
    const other = buildIssueBody({
      ticketId: "x",
      type: "feature",
      description: "Une idée de fonctionnalité",
      screen: "/recettes/aB3xYz9",
      appVersion: undefined,
      platform: "web",
    });
    assert.match(other, /^\*\*Écran :\*\* Non précisé$/m);
    assert.match(other, /^\*\*Version :\*\* Version inconnue$/m);
    assert.match(other, /^\*\*Type :\*\* Nouvelle fonctionnalité$/m);
    assert.match(other, /^\*\*Plateforme :\*\* Web$/m);
  });

  it("autre écran et écran inconnu", () => {
    for (const [screen, label] of [
      ["autre", "Autre écran"],
      ["inconnu", "Non précisé"],
    ]) {
      const b = buildIssueBody({
        ticketId: "x",
        type: "evolution",
        description: "dddddddddd",
        screen,
        appVersion: "1.0.0",
        platform: "web",
      });
      assert.ok(b.includes(`**Écran :** ${label}`), b);
    }
  });

  it("titre sur une ligne, nettoyé", () => {
    assert.equal(buildIssueTitle("Bug  \n de @moi"), "Bug de @\u200bmoi");
  });

  it("étiquettes de création", () => {
    assert.deepEqual(creationLabels("evolution"), [
      "source:app",
      "type:evolution",
      "statut:à-analyser",
    ]);
  });
});

describe("routeTemplateOrNull", () => {
  const ok = [
    "/",
    "/recettes",
    "/recettes/:id",
    "/recettes/:id/modifier",
    "/brassins/:id/fenetre/embouteillage",
    "/recettes/menu/compte",
    "autre",
    "inconnu",
  ];
  for (const value of ok)
    it(`${value} : accepté`, () => assert.equal(routeTemplateOrNull(value), value));
  const ko = ["/recettes/aB3xYz9", "/recettes/123", "recettes", "/recettes?x=1", "/a#b", "", 3];
  for (const value of ko)
    it(`${String(value)} : refusé`, () => assert.equal(routeTemplateOrNull(value), null));
});

describe("statut lu sur GitHub", () => {
  const cases: Array<[string, Parameters<typeof statusFromIssue>[0], PublishedStatus]> = [
    [
      "ouverte sans étiquette",
      { state: "open", stateReason: null, labels: ["source:app"] },
      "received",
    ],
    ["validé", { state: "open", stateReason: null, labels: ["validé"] }, "validated"],
    [
      "en cours",
      { state: "open", stateReason: null, labels: ["validé", "statut:en-cours"] },
      "in_progress",
    ],
    ["fermée completed", { state: "closed", stateReason: "completed", labels: [] }, "delivered"],
    ["fermée sans raison", { state: "closed", stateReason: null, labels: [] }, "delivered"],
    [
      "fermée statut:clos",
      { state: "closed", stateReason: "completed", labels: ["statut:clos"] },
      "closed",
    ],
    ["fermée not_planned", { state: "closed", stateReason: "not_planned", labels: [] }, "refused"],
    ["fermée duplicate", { state: "closed", stateReason: "duplicate", labels: [] }, "refused"],
  ];
  for (const [name, issue, expected] of cases) {
    it(`${name} → ${expected}`, () => assert.equal(statusFromIssue(issue), expected));
  }

  it("un statut ne recule pas", () => {
    assert.equal(nextStatus("in_progress", "validated"), "in_progress");
    assert.equal(nextStatus("validated", "received"), "validated");
    assert.equal(nextStatus("received", "validated"), "validated");
  });

  it("une fermeture l'emporte, une réouverture reprend les étiquettes", () => {
    assert.equal(nextStatus("in_progress", "refused"), "refused");
    assert.equal(nextStatus("delivered", "received"), "received");
    assert.equal(nextStatus("refused", "delivered"), "delivered");
  });
});

describe("plafond du jour", () => {
  const limits = { memberLimit: 5, groupLimit: 20 };
  it("5e ticket du membre publié, 6e refusé (membre)", () => {
    assert.equal(quotaRefusal({ isAdmin: false, memberCount: 4, groupCount: 4, ...limits }), null);
    assert.equal(
      quotaRefusal({ isAdmin: false, memberCount: 5, groupCount: 5, ...limits }),
      "member",
    );
  });
  it("21e ticket du groupe refusé (groupe)", () => {
    assert.equal(
      quotaRefusal({ isAdmin: false, memberCount: 0, groupCount: 20, ...limits }),
      "group",
    );
  });
  it("administrateur jamais refusé", () => {
    assert.equal(quotaRefusal({ isAdmin: true, memberCount: 99, groupCount: 99, ...limits }), null);
  });
  it("compteur illisible lu 0", () => {
    assert.equal(readCount(undefined), 0);
    assert.equal(readCount({ count: "3" }), 0);
    assert.equal(readCount({ count: 3 }), 3);
  });
  it("jour de Paris, heure d'hiver et d'été", () => {
    assert.equal(parisDay(new Date("2026-11-10T22:59:00Z")), "20261110");
    assert.equal(parisDay(new Date("2026-11-10T23:00:00Z")), "20261111");
    assert.equal(parisDay(new Date("2026-07-01T21:59:00Z")), "20260701");
    assert.equal(parisDay(new Date("2026-07-01T22:00:00Z")), "20260702");
  });
});

describe("réponse de l'administrateur", () => {
  const c = (authorId: number, body: string, createdAt = "2026-11-10T10:00:00Z"): CommentView => ({
    id: 1,
    authorId,
    body,
    createdAt,
    updatedAt: createdAt,
  });

  it("préfixe retiré, ligne « Décision » retirée", () => {
    assert.equal(
      replyFromComment(c(OWNER, "Réponse : C'est prévu.\nDécision d-42"), OWNER, 2000),
      "C'est prévu.",
    );
  });
  it("variantes du préfixe (espace insécable, é décomposé)", () => {
    assert.equal(replyFromComment(c(OWNER, "Réponse\u00a0: oui"), OWNER, 2000), "oui");
    assert.equal(replyFromComment(c(OWNER, "Re\u0301ponse : oui"), OWNER, 2000), "oui");
  });
  it("commentaire d'un autre compte ignoré, même avec le préfixe", () => {
    assert.equal(replyFromComment(c(1, "Réponse : faux"), OWNER, 2000), null);
  });
  it("commentaire du propriétaire sans le préfixe ignoré", () => {
    assert.equal(replyFromComment(c(OWNER, "Je regarde."), OWNER, 2000), null);
  });
  it("adresse remplacée, longueur bornée", () => {
    assert.equal(
      replyFromComment(c(OWNER, "Réponse : écrivez à a@exemple.fr"), OWNER, 2000),
      "écrivez à [adresse retirée]",
    );
    assert.equal(
      Array.from(replyFromComment(c(OWNER, `Réponse : ${"x".repeat(3000)}`), OWNER, 2000) ?? "")
        .length,
      2000,
    );
  });
  it("la dernière réponse du propriétaire l'emporte", () => {
    const reply = lastReply(
      [
        c(OWNER, "Réponse : première", "2026-11-01T00:00:00Z"),
        c(OWNER, "Réponse : seconde", "2026-11-02T00:00:00Z"),
        c(2, "Réponse : d'un tiers", "2026-11-03T00:00:00Z"),
      ],
      OWNER,
      2000,
    );
    assert.deepEqual(reply, { text: "seconde", at: "2026-11-02T00:00:00Z" });
  });
});

describe("livraison", () => {
  it("version lue sans le numéro de build", () => {
    assert.equal(pubspecVersionName("name: app\nversion: 0.2.3+40\n"), "0.2.3");
    assert.equal(pubspecVersionName("version: 0.2.3\n"), "0.2.3");
    assert.equal(pubspecVersionName("name: app\n"), null);
    assert.equal(pubspecVersionName("version: abc\n"), null);
  });

  it("commit de fermeture : dernier événement closed avec commit_id", () => {
    const events = [
      { event: "closed", commit_id: null, created_at: "2026-11-01T00:00:00Z" },
      { event: "closed", commit_id: "aaaaaaa1", created_at: "2026-11-02T00:00:00Z" },
      { event: "reopened", created_at: "2026-11-03T00:00:00Z" },
      { event: "closed", commit_id: "bbbbbbb2", created_at: "2026-11-04T00:00:00Z" },
    ];
    assert.equal(closingCommitFromEvents(events), "bbbbbbb2");
    assert.equal(closingCommitFromEvents([{ event: "closed", commit_id: null }]), null);
  });

  it("mots-clés de fermeture, autre dépôt ignoré", () => {
    assert.deepEqual(
      closingIssueNumbers("Closes #12, fixes ChinaFred/KassBeer#3, resolves other/repo#9", REPO),
      [3, 12],
    );
  });

  const pr = (extra: Partial<MergedPrCandidate>): MergedPrCandidate => ({
    number: 7,
    mergedAt: "2026-11-05T00:00:00Z",
    mergeCommitSha: "ccccccc3",
    body: "Closes #12",
    baseRepoFullName: REPO,
    authorId: OWNER,
    authorAssociation: "OWNER",
    ...extra,
  });

  it("PR fusionnée de n'importe quelle branche, adresse reconstruite", () => {
    assert.deepEqual(pickDeliveredPr([pr({})], 12, OWNER, REPO), {
      number: 7,
      url: "https://github.com/ChinaFred/KassBeer/pull/7",
      mergeCommitSha: "ccccccc3",
    });
  });
  it("PR non fusionnée, d'un autre dépôt, d'un tiers ou qui ne ferme pas l'Issue : écartée", () => {
    for (const extra of [
      { mergedAt: null },
      { baseRepoFullName: "fork/KassBeer" },
      { authorId: 1, authorAssociation: "NONE" },
      { body: "Voir #12" },
    ]) {
      assert.equal(pickDeliveredPr([pr(extra)], 12, OWNER, REPO), null, JSON.stringify(extra));
    }
  });
  it("plusieurs PR : la dernière fusionnée", () => {
    const picked = pickDeliveredPr(
      [pr({ number: 7 }), pr({ number: 9, mergedAt: "2026-11-06T00:00:00Z" })],
      12,
      OWNER,
      REPO,
    );
    assert.equal(picked?.number, 9);
  });
});

describe("échéance du jeton", () => {
  it("formats de l'en-tête", () => {
    assert.equal(
      parseTokenExpiration("2026-12-31 00:00:00 UTC")?.toISOString(),
      "2026-12-31T00:00:00.000Z",
    );
    assert.equal(
      parseTokenExpiration("2026-12-31 01:00:00 +0100")?.toISOString(),
      "2026-12-31T00:00:00.000Z",
    );
    assert.equal(parseTokenExpiration(null), null);
    assert.equal(parseTokenExpiration("demain"), null);
  });
});
