import 'dart:convert';
import 'dart:io';

import 'package:brewing/brewing.dart' show CostUnit, FeeBasis;
import 'package:exchange/exchange.dart'
    show kMaxOctetsParFichier, RecetteRefusee, RecetteIllisible;
import 'package:exchange/fiches.dart';
import 'package:test/test.dart';

/// Lecteur du format `kassbeer_fiches` v1 (v0.6, TE1). Fixture inventée :
/// noms fictifs, prix fictifs.
const _fixture = 'test/fixtures/fiches/fiches-valide.json';

final _maintenant = DateTime.utc(2026, 11, 13, 12);

Map<String, Object?> _fichier() =>
    jsonDecode(File(_fixture).readAsStringSync()) as Map<String, Object?>;

List<Object?> _fiches(Map<String, Object?> f) =>
    (f['kassbeer_fiches']! as Map<String, Object?>)['fiches']! as List<Object?>;

Map<String, Object?> _fiche(Map<String, Object?> f, int i) =>
    _fiches(f)[i]! as Map<String, Object?>;

LectureFiches _lire(Object? racine, {DateTime? maintenant}) =>
    lireFichierFiches(
      utf8.encode(jsonEncode(racine)),
      maintenant: maintenant ?? _maintenant,
    );

FichierFiches _lu(Object? racine, {DateTime? maintenant}) =>
    _lire(racine, maintenant: maintenant) as FichierFiches;

FicheLue _acceptee(FicheDuFichier f) => switch (f.resultat) {
  FicheAcceptee(:final fiche) => fiche,
  FicheRefusee(:final refus) => fail('fiche refusée : $refus'),
};

RefusFiche _refus(FicheDuFichier f) => switch (f.resultat) {
  FicheRefusee(:final refus) => refus,
  FicheAcceptee() => fail('fiche acceptée'),
};

/// Refus de la première fiche après [modifier].
RefusFiche _refusApres(void Function(Map<String, Object?> fiche) modifier) {
  final f = _fichier();
  modifier(_fiche(f, 0));
  final lu = _lu(f);
  // Les autres fiches restent lisibles.
  expect(lu.fiches[1].resultat, isA<FicheAcceptee>());
  return _refus(lu.fiches.first);
}

Map<String, Object?> _brew(Map<String, Object?> fiche) =>
    fiche['brew']! as Map<String, Object?>;

List<Object?> _events(Map<String, Object?> fiche) =>
    fiche['events']! as List<Object?>;

Map<String, Object?> _event(Map<String, Object?> fiche, int i) =>
    _events(fiche)[i]! as Map<String, Object?>;

Map<String, Object?> _cost(Map<String, Object?> fiche) =>
    fiche['cost']! as Map<String, Object?>;

void main() {
  group('fichier valide', () {
    test('trois fiches lues, champ par champ', () {
      final lu = _lu(_fichier());
      expect(lu.recettes, hasLength(2));
      expect(lu.fiches, hasLength(3));
      final blonde = _acceptee(lu.fiches[0]);
      expect(blonde.ficheId, '2024-07-14-blonde-essai');
      expect(blonde.recipeDocId, 'fiche-blonde-essai');
      expect(blonde.recipeIndex, 0);
      expect(blonde.recette.recipe['name'], "Blonde d'essai");
      expect(blonde.etapes.map((e) => e.key), [
        'empatage',
        'ebullition',
        'densite-initiale',
      ]);
      expect(blonde.etapes.first.tempC, 66);
      expect(blonde.brassin.bottlesCount, 50);
      expect(blonde.brassin.packagedVolumeL, 17);
      expect(blonde.brassin.primingSugarName, 'Sucre blanc');
      expect(blonde.brassin.equipementType, TypeEquipementFiche.cuves);
      expect(
        blonde.brassin.startAt,
        DateTime.parse('2024-07-14T09:00:00+02:00'),
      );
      expect(blonde.evenements, hasLength(7));
      expect(blonde.evenements[1].typeMesure, TypeMesureFiche.temperature);
      expect(blonde.evenements[1].valeur, 66.5);
      expect(blonde.ogEventId, 'e05');
      expect(blonde.fgEventId, isNull);
      expect(blonde.fermenterVolumeEventId, 'e06');
      final cout = blonde.cout!;
      expect(cout.prix.map((p) => p.key), [
        'malt-pils',
        'houblon-alpha',
        'levure-test',
      ]);
      expect(cout.prix.last.unit, CostUnit.unit);
      expect(cout.frais.last.basis, FeeBasis.perBottle);
      expect(cout.totalFicheEur, 17.5);
      expect(blonde.corrections.single.sujet, 'Densité finale');
      expect(blonde.deductions, hasLength(1));
      expect(blonde.divergences, hasLength(1));
      expect(blonde.nonImporte, hasLength(1));

      final ambree = _acceptee(lu.fiches[1]);
      expect(ambree.brassin.equipementType, TypeEquipementFiche.toutEnUn);
      expect(ambree.cout, isNull);
      expect(ambree.evenements.last.nature, NatureEvenementFiche.note);
      expect(ambree.evenements.last.fermentation, isTrue);
      expect(ambree.evenements[1].origineHeure, OrigineHeure.debutBrassage);
    });

    test('relevé estimé J+28 : daté par le fichier, après le brassage', () {
      final blonde = _acceptee(_lu(_fichier()).fiches.first);
      final releve = blonde.evenements.last;
      expect(releve.origineHeure, OrigineHeure.estimeeJ28);
      expect(releve.fermentation, isTrue);
      expect(releve.typeMesure, TypeMesureFiche.densite);
      expect(releve.valeur, 1.023);
      expect(releve.note, 'Date estimée : jour du brassage + 28 jours.');
      expect(releve.measuredAt, DateTime.parse('2024-08-11T12:00:00+02:00'));
      expect(releve.measuredAt.isAfter(blonde.brassin.startAt), isTrue);
    });

    test('empreinte : stable, et changée par une valeur de la fiche', () {
      final a = _lu(_fichier()).fiches.first.empreinte;
      expect(_lu(_fichier()).fiches.first.empreinte, a);
      expect(a, startsWith('sha256:'));
      final f = _fichier();
      _brew(_fiche(f, 0))['bottles_count'] = 49;
      expect(_lu(f).fiches.first.empreinte, isNot(a));
    });

    test('empreinte : changée par la recette de la fiche', () {
      final a = _lu(_fichier()).fiches.first.empreinte;
      final f = _fichier();
      final recettes =
          (f['beerjson']! as Map<String, Object?>)['recipes']! as List<Object?>;
      (recettes.first! as Map<String, Object?>)['notes'] = 'Autre note.';
      expect(_lu(f).fiches.first.empreinte, isNot(a));
    });

    test('contrôles bidirectionnels retirés des textes', () {
      final f = _fichier();
      _brew(_fiche(f, 0))['name'] = '\u202EBlonde\u202C d\'essai';
      _event(_fiche(f, 0), 6)['note'] = 'Date\u2066 estimée\u2069.';
      final blonde = _acceptee(_lu(f).fiches.first);
      expect(blonde.brassin.name, 'Blonde d\'essai');
      expect(blonde.evenements.last.note, 'Date estimée.');
    });

    test('aucune fiche : fichier lu, liste vide', () {
      final f = _fichier();
      (f['kassbeer_fiches']! as Map<String, Object?>)['fiches'] = <Object?>[];
      expect(_lu(f).fiches, isEmpty);
    });
  });

  group('fichier refusé', () {
    RaisonFichierFiches? raison(Object? racine) => switch (_lire(racine)) {
      FichierFichesRefuse(:final raison) => raison,
      FichierFiches() => null,
    };

    test('version de format inconnue', () {
      final f = _fichier();
      (f['kassbeer_fiches']! as Map<String, Object?>)['format_version'] = 2;
      expect(raison(f), RaisonFichierFiches.versionInconnue);
    });

    test('sans kassbeer_fiches, ou champ inconnu à la racine', () {
      final f = _fichier()..remove('kassbeer_fiches');
      expect(raison(f), RaisonFichierFiches.pasUnFichierDeFiches);
      final g = _fichier()..['autre'] = 1;
      expect(raison(g), RaisonFichierFiches.pasUnFichierDeFiches);
    });

    test('fichier BeerXML : pas un fichier de fiches', () {
      final xml = utf8.encode(
        '<?xml version="1.0"?><RECIPES><RECIPE><NAME>A</NAME></RECIPE>'
        '</RECIPES>',
      );
      expect(
        lireFichierFiches(xml, maintenant: _maintenant),
        isA<FichierFichesRefuse>().having(
          (r) => r.raison,
          'raison',
          RaisonFichierFiches.pasUnFichierDeFiches,
        ),
      );
    });

    test('plus de 10 Mo', () {
      final octets = List<int>.filled(kMaxOctetsParFichier + 1, 0x20);
      expect(
        lireFichierFiches(octets, maintenant: _maintenant),
        isA<FichierFichesRefuse>().having(
          (r) => r.raison,
          'raison',
          RaisonFichierFiches.tropGros,
        ),
      );
    });

    test('plus de 50 fiches', () {
      final f = _fichier();
      final fiches = _fiches(f);
      final modele = jsonEncode(fiches.first);
      fiches
        ..clear()
        ..addAll([
          for (var i = 0; i < 51; i++)
            (jsonDecode(modele) as Map<String, Object?>)
              ..['fiche_id'] = 'fiche-$i',
        ]);
      expect(raison(f), RaisonFichierFiches.tropDeFiches);
    });

    test('deux fiches au même identifiant', () {
      final f = _fichier();
      _fiche(f, 1)['fiche_id'] = '2024-07-14-blonde-essai';
      final lecture = _lire(f) as FichierFichesRefuse;
      expect(lecture.raison, RaisonFichierFiches.identifiantEnDouble);
      expect(lecture.ficheId, '2024-07-14-blonde-essai');
    });

    test('JSON mal formé : FormatException, comme analyserFichier', () {
      expect(
        () => lireFichierFiches(utf8.encode('{"a": '), maintenant: _maintenant),
        throwsFormatException,
      );
    });
  });

  group('fiche refusée, les autres lues', () {
    test('relevé daté après le jour de l\'import', () {
      final f = _fichier();
      final lu = _lu(f, maintenant: DateTime.utc(2024, 8, 1));
      expect(_refus(lu.fiches.first).chemin, 'events[6].measured_at');
      expect(_refus(lu.fiches.first).code, CodeRefusFiche.horsBornes);
      expect(lu.fiches[1].resultat, isA<FicheAcceptee>());
    });

    test('date avant 2015, date sans décalage, date impossible', () {
      expect(
        _refusApres(
          (fi) => _brew(fi)['start_at'] = '2014-12-31T09:00:00+01:00',
        ).code,
        CodeRefusFiche.horsBornes,
      );
      expect(
        _refusApres((fi) => _brew(fi)['start_at'] = '2024-07-14T09:00:00').code,
        CodeRefusFiche.formatInvalide,
      );
      expect(
        _refusApres(
          (fi) => _brew(fi)['start_at'] = '2024-13-14T09:00:00+02:00',
        ).code,
        CodeRefusFiche.formatInvalide,
      );
    });

    test('champ inconnu, dans la fiche et dans l\'équipement', () {
      final a = _refusApres((fi) => fi['avis'] = 'Très bonne');
      expect((a.chemin, a.code), ('avis', CodeRefusFiche.champInconnu));
      final b = _refusApres(
        (fi) => (_brew(fi)['equipment']! as Map)['rendement'] = 70,
      );
      expect(b.chemin, 'brew.equipment.rendement');
      expect(b.code, CodeRefusFiche.champInconnu);
    });

    test('champ obligatoire absent, type faux', () {
      final a = _refusApres((fi) => fi.remove('events'));
      expect((a.chemin, a.code), ('events', CodeRefusFiche.champAbsent));
      final b = _refusApres((fi) => _brew(fi)['bottles_count'] = '50');
      expect(b.code, CodeRefusFiche.typeInattendu);
      final c = _refusApres((fi) => _brew(fi)['bottles_count'] = 12.5);
      expect(c.code, CodeRefusFiche.typeInattendu);
    });

    test('step_key inconnue, clé d\'étape et identifiant en double', () {
      final a = _refusApres((fi) => _event(fi, 0)['step_key'] = 'inconnue');
      expect(
        (a.chemin, a.code),
        ('events[0].step_key', CodeRefusFiche.etapeInconnue),
      );
      final b = _refusApres((fi) {
        final steps = fi['brew_steps']! as List<Object?>;
        (steps[1]! as Map)['key'] = 'empatage';
      });
      expect(
        (b.chemin, b.code),
        ('brew_steps[1].key', CodeRefusFiche.enDouble),
      );
      final c = _refusApres((fi) => _event(fi, 2)['id'] = 'e01');
      expect((c.chemin, c.code), ('events[2].id', CodeRefusFiche.enDouble));
    });

    test('bornes des listes : étapes, événements, coût, divergences', () {
      expect(
        _refusApres((fi) {
          final steps = fi['brew_steps']! as List<Object?>;
          for (var i = 0; i < 58; i++) {
            steps.add({'key': 'k$i', 'name': 'É $i', 'duration_min': 1});
          }
        }).chemin,
        'brew_steps',
      );
      expect(
        _refusApres((fi) {
          final events = _events(fi);
          for (var i = 0; i < 294; i++) {
            events.add({
              'id': 'x$i',
              'kind': 'step_started',
              'step_key': 'empatage',
              'measured_at': '2024-07-14T09:15:00+02:00',
              'time_source': 'fiche',
            });
          }
        }).chemin,
        'events',
      );
      expect(
        _refusApres((fi) {
          final fees = _cost(fi)['fees']! as List<Object?>;
          for (var i = 0; i < 196; i++) {
            fees.add({'name': 'F$i', 'amount_eur': 1, 'basis': 'per_brew'});
          }
        }).chemin,
        'cost',
      );
      expect(
        _refusApres(
          (fi) => fi['divergences'] = [for (var i = 0; i < 201; i++) 'D$i'],
        ).chemin,
        'divergences',
      );
    });

    test('bornes des textes : nom, note, notes', () {
      expect(
        _refusApres((fi) => _brew(fi)['name'] = 'n' * 121).chemin,
        'brew.name',
      );
      expect(
        _refusApres((fi) => _event(fi, 1)['note'] = 'n' * 2001).chemin,
        'events[1].note',
      );
      expect(
        _refusApres((fi) => _brew(fi)['notes'] = 'n' * 10001).chemin,
        'brew.notes',
      );
    });

    test('bornes des mesures de firestore.rules', () {
      for (final (type, valeur) in [
        ('temperature', 110.5),
        ('temperature', -1),
        ('gravity', 0.97),
        ('gravity', 1.21),
        ('volume', 0),
        ('volume', 1001),
        ('ph', 14.1),
      ]) {
        final r = _refusApres((fi) {
          _event(fi, 1)
            ..['measure_type'] = type
            ..['value'] = valeur;
        });
        expect(
          (r.chemin, r.code),
          ('events[1].value', CodeRefusFiche.horsBornes),
          reason: '$type $valeur',
        );
      }
    });

    test('début d\'étape avec une valeur, note sans texte, phase inconnue', () {
      expect(
        _refusApres((fi) => _event(fi, 0)['value'] = 1).chemin,
        'events[0].value',
      );
      expect(
        _refusApres((fi) {
          _event(fi, 0)
            ..['kind'] = 'note'
            ..remove('step_key');
        }).chemin,
        'events[0].note',
      );
      expect(
        _refusApres((fi) => _event(fi, 6)['phase'] = 'garde').chemin,
        'events[6].phase',
      );
      expect(
        _refusApres((fi) => _event(fi, 0)['kind'] = 'step_ended').chemin,
        'events[0].kind',
      );
    });

    test('mesure retenue qui ne désigne pas le bon type', () {
      final r = _refusApres(
        (fi) => (fi['retained']! as Map)['og_event_id'] = 'e06',
      );
      expect(
        (r.chemin, r.code),
        ('retained.og_event_id', CodeRefusFiche.evenementInconnu),
      );
    });

    test('prix et frais aux bornes de prices et fees, sans valeur dans le '
        'refus', () {
      final r = _refusApres((fi) {
        final prix = _cost(fi)['prices']! as List<Object?>;
        (prix.first! as Map)['price_eur'] = 123456.78;
      });
      expect(
        (r.chemin, r.code),
        ('cost.prices[0].price_eur', CodeRefusFiche.horsBornes),
      );
      expect('$r', isNot(contains('123456')));
      final f = _refusApres((fi) {
        final frais = _cost(fi)['fees']! as List<Object?>;
        (frais.first! as Map)['amount_eur'] = 10000.01;
      });
      expect(f.chemin, 'cost.fees[0].amount_eur');
      final k = _refusApres((fi) {
        final prix = _cost(fi)['prices']! as List<Object?>;
        (prix[1]! as Map)['key'] = 'malt-pils';
      });
      expect(
        (k.chemin, k.code),
        ('cost.prices[1].key', CodeRefusFiche.enDouble),
      );
    });

    test('S1 : montant dans un texte lu par le groupe, refus sans valeur', () {
      for (final (modifier, chemin) in [
        (
          (Map<String, Object?> fi) => _brew(fi)['notes'] = 'Coût 39,24 €',
          'brew.notes',
        ),
        (
          (Map<String, Object?> fi) =>
              _event(fi, 0)['note'] = 'Prix du malt : 12 euros',
          'events[0].note',
        ),
        (
          (Map<String, Object?> fi) => _brew(fi)['name'] = 'Blonde à 20 EUR',
          'brew.name',
        ),
      ]) {
        final r = _refusApres(modifier);
        expect((r.chemin, r.code), (chemin, CodeRefusFiche.montant));
        expect('$r', isNot(contains('39')));
        expect('$r', isNot(contains('12')));
        expect('$r', isNot(contains('20')));
      }
    });

    test('S1 : montant dans les notes de la recette ; permis dans les '
        'divergences, lues par l\'administrateur seul', () {
      final f = _fichier();
      final recettes =
          (f['beerjson']! as Map<String, Object?>)['recipes']! as List<Object?>;
      (recettes.first! as Map<String, Object?>)['notes'] = 'Total 17,50 €';
      expect(_refus(_lu(f).fiches.first).code, CodeRefusFiche.montant);
      final g = _fichier();
      _fiche(g, 0)['divergences'] = ['Total de la fiche : 1 511,23 €.'];
      expect(_lu(g).fiches.first.resultat, isA<FicheAcceptee>());
    });

    test('S4 : adresse web dans le nom d\'un houblon de la recette', () {
      final f = _fichier();
      final recettes =
          (f['beerjson']! as Map<String, Object?>)['recipes']! as List<Object?>;
      final ingredients =
          (recettes.first! as Map<String, Object?>)['ingredients']!
              as Map<String, Object?>;
      final houblon =
          (ingredients['hop_additions']! as List<Object?>).first!
              as Map<String, Object?>;
      houblon['name'] = 'Houblon www.exemple.fr';
      final r = _refus(_lu(f).fiches.first);
      expect((r.chemin, r.code), ('recipe_index', CodeRefusFiche.adresseWeb));
    });

    test('adresse web dans les notes du brassin ou de la recette', () {
      expect(
        _refusApres(
          (fi) => _brew(fi)['notes'] = 'Voir https://exemple.fr/recette',
        ).code,
        CodeRefusFiche.adresseWeb,
      );
      final f = _fichier();
      final recettes =
          (f['beerjson']! as Map<String, Object?>)['recipes']! as List<Object?>;
      (recettes.first! as Map<String, Object?>)['notes'] = 'www.exemple.fr';
      final lu = _lu(f);
      expect(_refus(lu.fiches.first).code, CodeRefusFiche.adresseWeb);
      expect(lu.fiches[1].resultat, isA<FicheAcceptee>());
    });

    test('recette absente ou refusée par la lecture BeerJSON', () {
      expect(
        _refusApres((fi) => fi['recipe_index'] = 9).code,
        CodeRefusFiche.recetteAbsente,
      );
      final f = _fichier();
      final recettes =
          (f['beerjson']! as Map<String, Object?>)['recipes']! as List<Object?>;
      (recettes.first! as Map<String, Object?>).remove('name');
      final r = _refus(_lu(f).fiches.first);
      expect(r.code, CodeRefusFiche.recetteRefusee);
      expect(r.refusRecette, isNotNull);
      expect(r.refusRecette, isNot(isA<RecetteIllisible>()));
      expect(_lu(f).recettes.first.resultat, isA<RecetteRefusee>());
    });

    test('même recipe_doc_id, autre chronologie : la seconde refusée', () {
      final f = _fichier();
      final steps = _fiche(f, 2)['brew_steps']! as List<Object?>;
      (steps.first! as Map)['duration_min'] = 45;
      final lu = _lu(f);
      expect(lu.fiches.first.resultat, isA<FicheAcceptee>());
      expect(_refus(lu.fiches[2]).code, CodeRefusFiche.recetteIncoherente);
    });
  });

  group('vérificateur FO7', () {
    Future<ProcessResult> verifier(String chemin) => Process.run(
      Platform.resolvedExecutable,
      ['run', 'bin/verifier_fiches.dart', chemin],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );

    test('fichier valide : comptes, aucun prix affiché, code 0', () async {
      final r = await verifier(_fixture);
      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect(r.stdout, contains('Fiches : 3, 3 lues, 0 refusées.'));
      expect(
        r.stdout,
        contains('3 brassins, 2 recettes, 12 heures et mesures'),
      );
      expect(r.stdout, isNot(contains('17.5')));
      expect(r.stdout, isNot(contains('€')));
    });

    test('fiche refusée : chemin du champ, code 1', () async {
      final f = _fichier();
      _event(_fiche(f, 1), 0)['step_key'] = 'inconnue';
      final dossier = await Directory.systemTemp.createTemp('fiches');
      addTearDown(() => dossier.delete(recursive: true));
      final fichier = File('${dossier.path}/fiches.json')
        ..writeAsStringSync(jsonEncode(f));
      final r = await verifier(fichier.path);
      expect(r.exitCode, 1);
      expect(r.stdout, contains('fiche 2 (2023-04-02-ambree-essai)'));
      expect(r.stdout, contains('events[0].step_key'));
    });
  });
}
