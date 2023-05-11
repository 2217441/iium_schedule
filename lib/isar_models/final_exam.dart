import 'package:intl/intl.dart';
import 'package:isar/isar.dart';

part 'final_exam.g.dart';

enum ExamTime { am, pm }

/// Parse data from I-Ma'Luum importer for final exam
@collection
class FinalExam {
  Id? id;
  late String courseCode;

  /// Subject title
  late String title;
  late int section;

  /// Exam date with start time
  late DateTime date;

  /// am or pm
  @enumerated
  late ExamTime time;
  late String venue;
  late int seat;

  FinalExam(
      {required this.courseCode,
      required this.title,
      required this.section,
      required this.date,
      required this.time,
      required this.venue,
      required this.seat});

  FinalExam.fromJson(Map<String, dynamic> json) {
    courseCode = json["courseCode"];
    title = json["title"];
    section = json["section"];
    time = json["time"] == 'AM' ? ExamTime.am : ExamTime.pm;

    // This time component in this [date] is a start time
    var format = DateFormat('dd/MM/yyyy');
    date = format.parse(json["date"]);

    // From https://github.com/iqfareez/iium_schedule/discussions/84#discussioncomment-5829274
    // If morning (am), it starts at 9AM
    // If evening (pm), it starts at 2.30 PM except for Friday (3PM)
    if (time == ExamTime.am) {
      date = date.add(const Duration(hours: 9)); // 9AM
    } else {
      date = date.add(
        Duration(hours: 14, minutes: date.day == DateTime.friday ? 30 : 0),
      ); // 2PM or 2.30PM
    }
    venue = json["venue"];
    seat = json["seat"];
  }

  static List<FinalExam> fromList(List<dynamic> list) {
    return list.map((map) => FinalExam.fromJson(map)).toList();
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data["courseCode"] = courseCode;
    data["title"] = title;
    data["section"] = section;
    data["date"] = date;
    data["time"] = time;
    data["venue"] = venue;
    data["seat"] = seat;
    return data;
  }

  @override
  String toString() {
    return "ImaluumExam{courseCode: $courseCode, title: $title, section: $section, date: $date, time: $time, venue: $venue, seat: $seat}";
  }
}
