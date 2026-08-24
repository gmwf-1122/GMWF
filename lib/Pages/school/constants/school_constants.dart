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
        'Computer Arts',
        'Arts & Humanities',
        'General',
      ];
    }
    return const ['General'];
  }

  /// Four core compulsory subjects + General Science
  static const List<String> coreCompulsorySubjects = [
    'English',
    'Urdu',
    'Islamiyat',
    'Pakistan Studies',
    'General Science',
  ];

  /// Returns subject list tailored by Class / Grade and Academic Group
  static List<String> getSubjectsForGradeAndGroup(String grade, String academicGroup) {
    if (!isHighSchool(grade)) {
      // Primary & Middle Classes (KG-1 to 8th)
      return const [
        'English',
        'Urdu',
        'Mathematics',
        'General Science',
        'Islamiyat',
        'Social Studies',
        'Nazra Quran',
        'Computer Studies',
        'Drawing & Arts',
      ];
    }

    // High School (Pre-9th, 9th, 10th)
    final group = academicGroup.toLowerCase().trim();
    if (group.contains('computer') && group.contains('arts')) {
      return const [
        'English',
        'Urdu',
        'Islamiyat',
        'Pakistan Studies',
        'General Mathematics',
        'Computer Studies & Graphics',
        'Fine Arts',
        'General Science',
      ];
    } else if (group.contains('biology') || group.contains('bio')) {
      return const [
        'English',
        'Urdu',
        'Islamiyat',
        'Pakistan Studies',
        'Mathematics',
        'Physics',
        'Chemistry',
        'Biology',
      ];
    } else if (group.contains('computer') || group.contains('cs')) {
      return const [
        'English',
        'Urdu',
        'Islamiyat',
        'Pakistan Studies',
        'Mathematics',
        'Physics',
        'Chemistry',
        'Computer Science',
      ];
    } else if (group.contains('arts') || group.contains('humanities')) {
      return const [
        'English',
        'Urdu',
        'Islamiyat',
        'Pakistan Studies',
        'General Mathematics',
        'Civics & Economics',
        'General Science',
        'Education',
      ];
    }

    // General stream
    return const [
      'English',
      'Urdu',
      'Islamiyat',
      'Pakistan Studies',
      'General Mathematics',
      'General Science',
      'Computer Studies',
    ];
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
