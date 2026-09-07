class OrganizerWallet {
  const OrganizerWallet({
    required this.id,
    required this.organizerId,
    required this.balance,
    this.currency = 'credits',
    required this.updatedAt,
  });

  final String id;
  final String organizerId;
  final num balance;
  final String currency;
  final DateTime updatedAt;

  String get balanceLabel {
    if (balance == balance.roundToDouble()) {
      return '${balance.toInt()} CR';
    }
    return '${balance.toStringAsFixed(2)} CR';
  }

  factory OrganizerWallet.fromJson(Map<String, dynamic> json) {
    return OrganizerWallet(
      id: json['id'] as String,
      organizerId: json['organizer_id'] as String,
      balance: (json['balance'] as num?) ?? 0,
      currency: (json['currency'] as String?) ?? 'credits',
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}

enum OrganizerTxType {
  attendanceReward,
  withdrawal,
  bonus,
  refund,
  manualAdjustment;

  static OrganizerTxType fromString(String? value) {
    switch (value) {
      case 'withdrawal':
        return OrganizerTxType.withdrawal;
      case 'bonus':
        return OrganizerTxType.bonus;
      case 'refund':
        return OrganizerTxType.refund;
      case 'manual_adjustment':
        return OrganizerTxType.manualAdjustment;
      case 'attendance_reward':
      default:
        return OrganizerTxType.attendanceReward;
    }
  }

  bool get isCredit =>
      this == OrganizerTxType.attendanceReward ||
      this == OrganizerTxType.bonus;
}

class OrganizerTransaction {
  const OrganizerTransaction({
    required this.id,
    required this.organizerId,
    required this.amount,
    required this.type,
    required this.description,
    required this.createdAt,
    this.eventId,
    this.participantId,
    this.eventTitle,
    this.participantNickname,
  });

  final String id;
  final String organizerId;
  final num amount;
  final OrganizerTxType type;
  final String description;
  final DateTime createdAt;
  final String? eventId;
  final String? participantId;
  final String? eventTitle;
  final String? participantNickname;

  String get amountLabel {
    final sign = type.isCredit ? '+' : '';
    final v = amount == amount.roundToDouble()
        ? '${amount.toInt()}'
        : amount.toStringAsFixed(2);
    return '$sign$v';
  }

  factory OrganizerTransaction.fromJson(Map<String, dynamic> json) {
    String? eventTitle;
    final event = json['event'] ?? json['events'];
    if (event is Map) {
      eventTitle = event['title'] as String?;
    }

    return OrganizerTransaction(
      id: json['id'] as String,
      organizerId: json['organizer_id'] as String,
      amount: (json['amount'] as num?) ?? 0,
      type: OrganizerTxType.fromString(json['type'] as String?),
      description: (json['description'] as String?) ?? '',
      createdAt: DateTime.parse(json['created_at'] as String),
      eventId: json['event_id'] as String?,
      participantId: json['participant_id'] as String?,
      eventTitle: eventTitle,
      participantNickname: json['participant_nickname'] as String?,
    );
  }
}

class OrganizerDashboardStats {
  const OrganizerDashboardStats({
    required this.eventsCount,
    required this.participantsCount,
    required this.confirmedToday,
    required this.balance,
  });

  final int eventsCount;
  final int participantsCount;
  final int confirmedToday;
  final num balance;

  String get balanceLabel {
    if (balance == balance.roundToDouble()) {
      return '${balance.toInt()} CR';
    }
    return '${balance.toStringAsFixed(2)} CR';
  }

  factory OrganizerDashboardStats.fromJson(Map<String, dynamic> json) {
    return OrganizerDashboardStats(
      eventsCount: (json['events_count'] as num?)?.toInt() ?? 0,
      participantsCount: (json['participants_count'] as num?)?.toInt() ?? 0,
      confirmedToday: (json['confirmed_today'] as num?)?.toInt() ?? 0,
      balance: (json['balance'] as num?) ?? 0,
    );
  }
}
