import 'dart:async';
import 'dart:math' as math; 

import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class AudioStreamClient {
  final http.Client _httpClient = http.Client();

  AudioStreamClient(); 

  static const Map<String, String> _defaultHeaders = {
    'user-agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/93.0.4577.63 Safari/537.36',
    'cookie': 'CONSENT=YES+cb', 
    'accept':
        'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.9',
    'accept-language': 'en-US,en;q=0.9',
    'sec-fetch-dest': 'document',
    'sec-fetch-mode': 'navigate',
    'sec-fetch-site': 'none',
    'sec-fetch-user': '?1',
    'upgrade-insecure-requests': '1',
  };

  Stream<List<int>> getAudioStream(
    StreamInfo streamInfo, {
    required int start,
    required int end,
    bool isThrottledOrVeryLarge = false, 
  }) =>
      _getStream(
        streamInfo,
        streamClient: this,
        start: start,
        end: end,
        isThrottledOrVeryLarge: isThrottledOrVeryLarge,
      );

  Stream<List<int>> _getStream(
    StreamInfo streamInfo, {
    Map<String, String> headers = const {},
    bool validate = true,
    required int start,
    required int end,
    int errorCount = 0,
    required AudioStreamClient streamClient,
    bool isThrottledOrVeryLarge = false, 
  }) async* {
    var currentChunkStart = start;

    final int downloadChunkSize = isThrottledOrVeryLarge ? 10379935 : (end - start); //10mb is the size, lets try 5mb later to see if download speed is better or not

    while (currentChunkStart < end) {

      final currentChunkEnd = math.min(currentChunkStart + downloadChunkSize, end);

      final int requestTo = currentChunkEnd -1;

      if (currentChunkStart > requestTo) { 
        break; 
      }

      var url = streamInfo.url; 

      try {
        final response = await retry(this, () async {
          final from = currentChunkStart;
          final to = requestTo; 

          late final http.Request request;

          if (url.queryParameters['c'] == 'ANDROID' || url.host.contains('googlevideo.com')) { 
            request = http.Request('get', url);
            request.headers['Range'] = 'bytes=$from-$to';
          } else {

            url = url.replace(queryParameters: {
              ...url.queryParameters,
              'range': '$from-$to' 
            });
            request = http.Request('get', url);
          }
          return send(request);
        });

        if (validate) {
          try {
            _validateResponse(response, response.statusCode);
          } on FatalFailureException {

            rethrow; 
          }
        }

        final chunkStreamController = StreamController<List<int>>();
        int bytesReceivedForThisChunk = 0;

        response.stream.listen(
          (data) {
            bytesReceivedForThisChunk += data.length;
            chunkStreamController.add(data);
          },
          onError: (e) {

            chunkStreamController.addError(e);
            chunkStreamController.close(); 
          },
          onDone: () {
            chunkStreamController.close(); 
          },
          cancelOnError: true, 
        );

        await for (final dataChunk in chunkStreamController.stream) {
          yield dataChunk;
        }

        currentChunkStart += bytesReceivedForThisChunk;
        errorCount = 0; 

        if (bytesReceivedForThisChunk < (currentChunkEnd - (currentChunkStart - bytesReceivedForThisChunk)) && currentChunkStart < end) {
            if (bytesReceivedForThisChunk == 0 && response.statusCode == 206) { 

            } else if (bytesReceivedForThisChunk == 0 && response.statusCode != 200 && response.statusCode != 206) {
                throw Exception('Chunk download received no data with status: ${response.statusCode}');
            }

        }

      } on HttpClientClosedException {

        break; 
      } on Exception catch (e) {

        if (errorCount >= 4) { 
          rethrow; 
        }
        errorCount++;
        await Future.delayed(Duration(milliseconds: 500 * errorCount)); 

      }
    }
  }

  void _validateResponse(http.BaseResponse response, int statusCode) {
    final request = response.request!;

    if (request.url.host.endsWith('.google.com') &&
        request.url.path.startsWith('/sorry/')) {
      throw RequestLimitExceededException.httpRequest(response);
    }

    if (statusCode >= 500) {
      throw TransientFailureException.httpRequest(response);
    }
    if (statusCode == 429) { 
      throw RequestLimitExceededException.httpRequest(response);
    }

    if (statusCode >= 400 && statusCode != 416) { 
      throw FatalFailureException.httpRequest(response);
    }
    if (statusCode == 416) {

        print('Warning: Received 416 Range Not Satisfiable for ${request.headers['Range']}');
    }
  }

  Future<T> retry<T>(
    AudioStreamClient? client, 
    FutureOr<T> Function() function,
  ) async {
    var retriesLeft = 5; 
    var attempt = 0;
    while (true) {
      try {
        return await function();
      } on Exception catch (e) {
        attempt++;
        retriesLeft -= getExceptionCost(e); 
        if (retriesLeft <= 0) {
          rethrow;
        }

        await Future.delayed(Duration(milliseconds: 500 * attempt));
      }
    }
  }

  int getExceptionCost(Exception e) {
    if (e is RequestLimitExceededException) {
      return 2; 
    }
    if (e is FatalFailureException) {
      return 3; 
    }
    return 1; 
  }

  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    _defaultHeaders.forEach((key, value) {
      if (!request.headers.containsKey(key)) {
        request.headers[key] = value;
      }
    });
    return _httpClient.send(request);
  }

  void close() {
    _httpClient.close();
  }
}