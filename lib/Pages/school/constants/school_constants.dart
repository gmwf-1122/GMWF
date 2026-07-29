// lib/pages/school/constants/school_constants.dart

class SchoolConstants {
  static const List<String> grades = [
    'KG-1',
    'KG-2',
    '1',
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8',
    'Pre-9th',
    '9th',
    '10th',
  ];

  static const List<String> filterGrades = [
    'All',
    'KG-1',
    'KG-2',
    '1',
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8',
    'Pre-9th',
    '9th',
    '10th',
  ];

  static const List<String> sections = ['A', 'B', 'C', 'D'];

  static bool isHighSchool(String grade) {
    final g = grade.toLowerCase().trim();
    return g == 'pre-9th' || g == '9th' || g == '10th';
  }

  static List<String> getAcademicGroupsForGrade(String grade) {
    if (isHighSchool(grade)) {
      return const [
        'Science (Computer Science)',
        'Science (Biology)',
        'Arts & Humanities',
        'General',
      ];
    }
    return const ['General'];
  }

  static const Map<String, double> defaultTuitionFees = {
    'KG-1': 2000.0,
    'KG-2': 2200.0,
    '1': 2500.0,
    '2': 2500.0,
    '3': 2800.0,
    '4': 2800.0,
    '5': 3000.0,
    '6': 3200.0,
    '7': 3500.0,
    '8': 3800.0,
    'Pre-9th': 4000.0,
    '9th': 4500.0,
    '10th': 5000.0,
  };
}
