  class Patient {
    final Map<String, dynamic> _data;

    Patient(this._data);

    // ---- Map-style access (CRITICAL) ----
    dynamic operator [](String key) => _data[key];

    // ---- Typed helpers (optional) ----
    String get cnic => _data['cnic'] ?? '';
    String get name => _data['name'] ?? '';
    bool get isAdult => _data['isAdult'] ?? true;

    // ---- Serialization ----
    factory Patient.fromMap(Map<String, dynamic> map) {
      return Patient(Map<String, dynamic>.from(map));
    }

    Map<String, dynamic> toMap() => Map<String, dynamic>.from(_data);
  }
