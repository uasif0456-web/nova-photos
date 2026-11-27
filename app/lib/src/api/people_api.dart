/// People API — `GET /people`, `GET/PUT/DELETE /people/{id}`,
/// merge, reassign, thumbnail. Hand-written from spec v3.4.2.
///
/// Faces depend on the server's `facialRecognition` feature flag —
/// gate the People UI on `ServerFeatures.facialRecognition`.
library;

import '../models/person.dart';
import 'api_client.dart';

class PeopleApi {
  const PeopleApi(this.client);

  final ImmichApiClient client;

  /// `GET /people` — all people (optionally including hidden ones).
  Future<List<Person>> listPeople({bool withHidden = false}) async {
    final response = await client.get('/people', query: {
      'withHidden': withHidden,
    });
    final list = client.decodeJsonList(response);
    return list
        .whereType<Map<String, Object?>>()
        .map(Person.fromJson)
        .toList(growable: false);
  }

  /// `GET /people/{id}`.
  Future<Person> getPerson(String id) async {
    final response = await client.get('/people/$id');
    return Person.fromJson(client.decodeJson(response));
  }

  /// `POST /people` — create a person (e.g. for a manually named face).
  Future<Person> createPerson({required String name}) async {
    final response = await client.post('/people', body: {'name': name});
    return Person.fromJson(client.decodeJson(response));
  }

  /// `PATCH /people/{id}` — rename, set birth date, favorite, hidden,
  /// feature face. PATCH is preferred over PUT (v4 migration note).
  Future<Person> updatePerson(
    String id, {
    String? name,
    String? birthDate,
    bool? isFavorite,
    bool? isHidden,
  }) async {
    final response = await client.patch('/people/$id', body: {
      'name': ? name,
      'birthDate': ? birthDate,
      'isFavorite': ? isFavorite,
      'isHidden': ? isHidden,
    });
    return Person.fromJson(client.decodeJson(response));
  }

  /// `DELETE /people/{id}`.
  Future<void> deletePerson(String id) async {
    final response = await client.delete('/people/$id');
    client.decodeJson(response);
  }

  /// `POST /people/merge` — merge several people into one.
  Future<void> mergePeople({
    required String targetId,
    required List<String> sourceIds,
  }) async {
    final response = await client.post('/people/merge', body: {
      'id': targetId,
      'ids': sourceIds,
    });
    client.decodeJson(response);
  }

  /// `PUT /people/{id}/reassign` — move faces from one person to another.
  Future<void> reassignFaces({
    required String fromPersonId,
    required String toPersonId,
    required List<String> faceIds,
  }) async {
    final response = await client.put(
      '/people/$toPersonId/reassign',
      body: {'personId': fromPersonId, 'faceIds': faceIds},
    );
    client.decodeJson(response);
  }

  /// `GET /people/{id}/statistics` — asset counts for a person.
  Future<Map<String, Object?>> getStatistics(String id) async {
    final response = await client.get('/people/$id/statistics');
    return client.decodeJson(response);
  }

  /// `GET /people/{id}/thumbnail` — raw thumbnail bytes.
  Future<List<int>> getThumbnailBytes(String id) async {
    final response = await client.getBytes('/people/$id/thumbnail');
    return client.decodeBytes(response);
  }
}
