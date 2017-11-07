import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:html/parser.dart' show parse;
import 'package:intl/intl.dart' show DateFormat;


List channelsList;
const RETRY = 30;

/// offset : [integer] defaults to 1000
///
/// returns channel = {chId, name}
///
fetchChannels([int offset]) async {
  var httpClient = createHttpClient();

  if(offset == null || offset == 0) offset = 10000;

  var url = "http://www.tatasky.com/tvguiderv/channels?startIndex=0&genreStr=99&subGenre=&offset=" + offset.toString();
  var response = await httpClient.read(url);

  Map responseJSON = JSON.decode(response);
  var data = parse(responseJSON["data"]);
  var heads = data.getElementsByClassName('channel-head');

  var _channels = [];

  for(var head in heads) {
    List ch = head.text.split(' - ');

    String _chId = ch.removeAt(0).toString().trim();
    String _name = (ch.reduce((value, element) => value + element)).toString().trim();

    var _channel = {
      "chId": _chId,
      "name": _name
    };
    _channels.add(_channel);
  }

  return _channels;
}


/// chId : channel identifier
/// date : {optional} defaults to current date
///
/// returns listing {
///  chId,
///  date,
///  episodes [name, startTime, duration]
/// }
///
fetchListing(int chId, { DateTime date, int retryCount }) async {

  if(null == retryCount) retryCount = 0;

  var httpClient = createHttpClient();
  String _dateStr;
  String _channel = await _idToChannelMapper(chId.toString());
  if(null == date) date = new DateTime.now();
  _dateStr = _convertDate(date);

  String _day = getDay(date.toString());

  String url = "http://www.tatasky.com/tvguiderv/readfiles.jsp?fileName=" +
            _dateStr + "/" + chId.toString().padLeft(5, '0') + "_event.json";

  Map headers= new Map();
  headers["Referer"] = "http://www.tatasky.com/tvguiderv/";
  headers["Accept"] = "application/json, text/javascript, */*; q=0.01";
  headers["Host"] = "www.tatasky.com";

  var response = await httpClient.read(url, headers: headers);
  var responseJSON;
  try{
    responseJSON = JSON.decode(response);
  } catch(e) {

    if(retryCount == RETRY) return {
      "chId": chId,
      "channel": _channel,
      "date": date,
      "day": _day,
      "episodes": "NA",
      "error": e
    };

    return fetchListing(chId, date: date, retryCount: retryCount + 1);
  }

  List episodes = [];

  if(null != responseJSON["eventList"]) {
    for(var event in responseJSON["eventList"]) {

      double _duration = transformDuration(event["ed"]);
      String _startTime = transformTime(event["st"]);
      Map _episode = {
        "name": event["et"],
        "channel": _channel,
        "startTime": _startTime,
        "duration": _duration.toStringAsFixed(2),
        "day": _day,
      };
      episodes.add(_episode);
    }
  }

  Map _listing = {
    "chId": chId,
    "channel": _channel,
    "date": date,
    "day": _day,
    "episodes": episodes
  };

  return _listing;
}


/// chId : channel identifier
/// date : {optional} defaults to current date
/// days : {optional} number of days from specified date
///
/// returns [listing]
///
fetchListingsFor(int chId, {DateTime date, int days}) async {
  List<String> _listings = [];

  if(date == null) date = new DateTime.now();

  for(var day = 0; day < days; day++) {
    _listings.add(await fetchListing(chId, date: date.add(new Duration(days: day))));
  }

  return _listings;
}

/// Converts DateTime to YYYYMMDD
/// date : DateTime
///
/// returns date YYYYMMDD
///
String _convertDate(DateTime date) {
  return (
    date.year.toString() +
    date.month.toString().padLeft(2, '0') +
    date.day.toString().padLeft(2, '0')
  );
}


/// Maps channel ID to channel Name
/// chId : chId
///
/// returns String
///
_idToChannelMapper(String chId) async {
  if(channelsList == null) channelsList = await fetchChannels();
  for(Map channel in channelsList) {
    if (channel["chId"] == chId) return channel["name"];
  }
  return null;
}

///
/// Search wiki for listing, check if a match can be obtained with infobox
///
searchShow(String search, String listing) {

}


/// Transforms minutes to HH:MM format
/// minutes: int
///
/// returns Double
///
double transformDuration(int minutes) {
  if(minutes < 60)
    return minutes/ 100;
  else {
    int _hours = 0;
    while(minutes > 60) {
      minutes -= 60;
      _hours = _hours + 1;
    }
    return _hours.roundToDouble() + (minutes / 100);
  }
}

/// Transforms date to HH:MM[am/pm] format
/// time: String
///
/// returns Double
///
String transformTime(String time) {
  List _list = time.split(":");
  _list.removeLast();
  
  String _minutes = _list.removeLast().toString();
  int _hours = int.parse(_list.removeLast());
  String _marker;

  if(_hours > 12) {
    _hours -= 12;
    _marker = "pm";
  } else if(_hours == 12)
    _marker = "pm";
  else {
    if(_hours == 0) _hours = 12;
    _marker = "am";
  }

  String _time = "$_hours:$_minutes$_marker";
  return _time;
}

///
///
///
getDay(String date) {
  DateFormat formatter = new DateFormat('yyyy-MM-dd');
  DateTime now = DateTime.parse(formatter.format(new DateTime.now()));

  List _date = date.split(" ")[0].split("-");
  DateTime _channelDate = new DateTime(int.parse(_date[0]), int.parse(_date[1]), int.parse(_date[2]));
  if(_channelDate.difference(now).inDays == 0) {
    return "Today";
  } else if(_channelDate.difference(now).inDays == 1) {
    return "Tomorrow";
  }
  List days = ["Monday", 'Tuesday', "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"];
  return (days[_channelDate.weekday - 1]);
}