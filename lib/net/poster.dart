import '../engine/api_requests.dart';

class Posted {
  final int status;
  final String body;

  const Posted(this.status, this.body);
}

abstract class Poster {
  Future<Posted> send(ApiCall call);
}
