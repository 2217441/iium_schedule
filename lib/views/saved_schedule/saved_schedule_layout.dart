import 'dart:io';

import 'package:albiruni/albiruni.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:provider/provider.dart';

// pull-to-refresh implementation
import 'package:pull_to_refresh/pull_to_refresh.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../constants.dart';

import '../../hive_model/saved_schedule.dart';
import '../../hive_model/saved_subject.dart';
import '../../providers/saved_subjects_provider.dart';
import '../../providers/schedule_layout_setting_provider.dart';
import '../../util/course_validator_pass.dart';
import '../../util/lane_events_util.dart';
import '../../util/subject_fetcher.dart';
import '../scheduler/schedule_view/rename_dialog.dart';
import '../scheduler/schedule_view/setting_bottom_sheet.dart';
import '../scheduler/schedule_view/timetable_view_widget.dart';
import 'add_subject_page.dart';
import 'metadata_dialog.dart';
import 'schedule_export_page.dart';

class SavedScheduleLayout extends StatefulWidget {
  SavedScheduleLayout({Key? key, required this.savedSchedule})
      : super(key: key);

  final SavedSchedule savedSchedule;
  final _box = Hive.box<SavedSchedule>(kHiveSavedSchedule);

  @override
  State<SavedScheduleLayout> createState() => _SavedScheduleLayoutState();
}

class _SavedScheduleLayoutState extends State<SavedScheduleLayout> {
  late String name;

  bool _isFullScreen = false;
  bool _hideFab = false;

  final RefreshController _refreshController = RefreshController(initialRefresh: false);
  
  // Let users keep track of what is currently fetching from the IIUM's database
  String currentRefreshCourse = '';
  
  // Initialize course validator
  late CourseValidatorPass _courseValidator;

  @override
  void initState() {
    super.initState();
    name = widget.savedSchedule.title ?? "";
    Provider.of<SavedSubjectsProvider>(context, listen: false).savedSubjects =
        widget.savedSchedule.subjects!;

    Provider.of<ScheduleLayoutSettingProvider>(context, listen: false)
        .initialConditionSubjectTitle(widget.savedSchedule.subjectTitleSetting);

    _courseValidator = CourseValidatorPass(widget.savedSchedule.subjects!.length);

  }

  void _onRefresh() async {
    
    /*
      NOTE:
      For now, we only use data from the title field of the SavedSchedule object.

      TODO: Save student's kuliyyah into HiveDB
    */

    // Get kuliyyah code (e.g: KICT) from tokenized title
    final kuliyyah = name.split(' ').elementAt(0);

    // Keep track of the current subject index
    var currentIndex = 0;

    // Here, we loop through each of student's saved subject and get the latest data from IIUM's database
    await Future.forEach<SavedSubject>(widget.savedSchedule.subjects!.toList(), (subject) async {

      // Update state of the pull-to-refresh loading text
      setState(() => currentRefreshCourse = 'Getting latest data for ${subject.subjectName}');

      final response = await SubjectFetcher.fetchSubjectData(
        albiruni: Albiruni(
          semester: widget.savedSchedule.semester,
          session: widget.savedSchedule.session
        ),
        kulliyyah: kuliyyah,
        courseCode: subject.code,
        section: subject.sect
      );

      _courseValidator.subjectSuccess(currentIndex++, response);

    });

    if (!_courseValidator.isClearToProceed()) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('We\'re facing some issues while fetching latest data. Try again later.')));
      return;
    }

    // Update student's hiveDB SavedSchedule with the latest subject
    SavedSchedule currentSchedule = widget._box.get(0)!;
    currentSchedule.subjects = _courseValidator.fetchedSubjects().map((subject) => SavedSubject.fromSubject(subject: subject)).toList();
    widget._box.put(0, currentSchedule);

    // Finish the refreshing state
    _refreshController.refreshCompleted();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SavedSubjectsProvider>(
      builder: (context, value, _) {
        LaneEventsResponse laneEventsList = LaneEventsUtil(
                context: context,
                fontSize: widget.savedSchedule.fontSize,
                savedSubjectList: value.savedSubjects)
            .laneEvents();
        return GestureDetector(
          onTap: _hideFab ? () => setState(() => _hideFab = !_hideFab) : null,
          // We want all the widgets to translate its position downwards as the student swipes
          // down the TimetableViewWidget, instead of showing the boring refresh indicator
          child: RefreshConfiguration(
            // Other refresh headers can be found from https://pub.dev/packages/pull_to_refresh#screenshots
            headerBuilder: () => ClassicHeader(
              refreshingText: currentRefreshCourse,
            ),
            child: Scaffold(
              appBar: _isFullScreen
                  ? null
                  : AppBar(
                      title: InkWell(
                          onTap: () async {
                            final scheduleNameController =
                                TextEditingController(text: name);
                            String? newName = await showDialog(
                                context: context,
                                builder: (_) => RenameDialog(
                                    scheduleNameController:
                                        scheduleNameController));
          
                            if ((newName == null) || (newName.isEmpty)) return;
                            setState(() => name = newName);
          
                            // save the new name and record the last modified
                            widget.savedSchedule.title = newName;
                            widget.savedSchedule.save();
                          },
                          child: Text(
                            name,
                            overflow: TextOverflow.fade,
                          )),
                      actions: [
                        IconButton(
                          tooltip: "Add subject",
                          icon: const Icon(Icons.add),
                          onPressed: () async {
                            var res = await Navigator.of(context).push(
                              MaterialPageRoute(
                                fullscreenDialog: true,
                                builder: (context) => AddSubjectPage(
                                  session: widget.savedSchedule.session,
                                  semester: widget.savedSchedule.semester,
                                ),
                              ),
                            );
          
                            if (res == null) return;
          
                            value.addSubject(res);
                          },
                        ),
                        if (kIsWeb || !Platform.isAndroid) ...[
                          IconButton(
                            tooltip: 'Increase text sizes',
                            onPressed: () {
                              setState(() => widget.savedSchedule.fontSize--);
                              widget.savedSchedule.save();
                            },
                            icon: const Icon(Icons.text_decrease_rounded),
                          ),
                          IconButton(
                            tooltip: 'Reduce text sizes',
                            onPressed: () {
                              setState(() => widget.savedSchedule.fontSize++);
                              widget.savedSchedule.save();
                            },
                            icon: const Icon(Icons.text_increase_rounded),
                          ),
                        ],
                        IconButton(
                            onPressed: () {
                              // open bottomsheet
                              showModalBottomSheet(
                                  context: context,
                                  builder: (_) => SettingBottomSheet(
                                        savedSchedule: widget.savedSchedule,
                                      ));
                            },
                            icon: const Icon(Icons.settings_outlined)),
                        PopupMenuButton(
                            itemBuilder: (context) {
                              return <PopupMenuEntry>[
                                PopupMenuItem(
                                  value: 'save',
                                  // when changing the item below
                                  // don't forget to also change
                                  // in schedule_layout.dart
                                  child: Text(kIsWeb
                                      ? 'Export'
                                      : Platform.isAndroid
                                          ? 'Export & share'
                                          : 'Export'),
                                ),
                                const PopupMenuDivider(),
                                const PopupMenuItem(
                                    value: 'metadata', child: Text('Metadata')),
                                // const PopupMenuItem(
                                //   // TODO: Implement delete
                                //   value: 'delete',
                                //   child: Text('Delete'),
                                // ),
                              ];
                            },
                            onSelected: popupMenuHandler),
                      ],
                    ),
              body: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  // pull-to-refresh implementation here
                  child: SmartRefresher(
                    controller: _refreshController,
                    onRefresh: _onRefresh,
                    child: TimetableViewWidget(
                      startHour: laneEventsList.startHour,
                      endHour: laneEventsList.endHour,
                      laneEventsList: laneEventsList.laneEventsList,
                      itemHeight: widget.savedSchedule.heightFactor,
                    )
                  )
                ),
              ),
              floatingActionButton: _hideFab
                  ? null
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.savedSchedule.heightFactor <= 90)
                          FloatingActionButton(
                              heroTag: "btnZoom+",
                              tooltip: "Zoom in (increase height)",
                              mini: true,
                              child: const Icon(Icons.zoom_in),
                              onPressed: () {
                                setState(
                                    () => widget.savedSchedule.heightFactor += 2);
                                widget.savedSchedule.save();
                              }),
                        if (kIsWeb || !Platform.isAndroid)
                          const SizedBox(height: 5),
                        if (widget.savedSchedule.heightFactor >= 44)
                          FloatingActionButton(
                              heroTag: "btnZoom-",
                              tooltip: "Zoom out (decrease height)",
                              mini: true,
                              child: const Icon(Icons.zoom_out),
                              onPressed: () {
                                setState(
                                    () => widget.savedSchedule.heightFactor -= 2);
                                widget.savedSchedule.save();
                              }),
                        if (kIsWeb || !Platform.isAndroid)
                          const SizedBox(height: 5),
                        FloatingActionButton(
                          heroTag: "btnFull",
                          mini: true,
                          tooltip: "Go full screen",
                          onPressed: fullscreenFabHandler,
                          child: Icon(_isFullScreen
                              ? Icons.fullscreen_exit
                              : Icons.fullscreen),
                        ),
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }

  void popupMenuHandler(value) {
    switch (value) {
      case 'save':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ScheduleExportPage(
                scheduleTitle: name,
                laneEventsResponse: LaneEventsUtil(
                        context: context,
                        fontSize: widget.savedSchedule.fontSize,
                        savedSubjectList:
                            Provider.of<SavedSubjectsProvider>(context)
                                .savedSubjects)
                    .laneEvents(),
                itemHeight: widget.savedSchedule.heightFactor),
          ),
        );
        break;
      case 'metadata':
        showModalBottomSheet(
            context: context,
            builder: (_) => MetadataSheet(
                  savedSchedule: widget.savedSchedule,
                ));
        break;
      case 'delete':
        // TODO: Implement delete
        Fluttertoast.showToast(msg: "Not implemented yet");
        throw UnimplementedError();
      // break;
    }
  }

  void fullscreenFabHandler() {
    if (!_isFullScreen) {
      // make full screen
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
      setState(() {
        _isFullScreen = true;
        _hideFab = true;
      });
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      setState(() => _isFullScreen = false);
    }
  }
}
