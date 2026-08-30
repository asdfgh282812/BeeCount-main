// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'db.dart';

// ignore_for_file: type=lint
class $LedgersTable extends Ledgers with TableInfo<$LedgersTable, Ledger> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LedgersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _currencyMeta =
      const VerificationMeta('currency');
  @override
  late final GeneratedColumn<String> currency = GeneratedColumn<String>(
      'currency', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('CNY'));
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
      'type', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('personal'));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _syncIdMeta = const VerificationMeta('syncId');
  @override
  late final GeneratedColumn<String> syncId = GeneratedColumn<String>(
      'sync_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _myRoleMeta = const VerificationMeta('myRole');
  @override
  late final GeneratedColumn<String> myRole = GeneratedColumn<String>(
      'my_role', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('owner'));
  static const VerificationMeta _memberCountMeta =
      const VerificationMeta('memberCount');
  @override
  late final GeneratedColumn<int> memberCount = GeneratedColumn<int>(
      'member_count', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(1));
  static const VerificationMeta _isSharedMeta =
      const VerificationMeta('isShared');
  @override
  late final GeneratedColumn<bool> isShared = GeneratedColumn<bool>(
      'is_shared', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_shared" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _ownerUserIdMeta =
      const VerificationMeta('ownerUserId');
  @override
  late final GeneratedColumn<String> ownerUserId = GeneratedColumn<String>(
      'owner_user_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _monthStartDayMeta =
      const VerificationMeta('monthStartDay');
  @override
  late final GeneratedColumn<int> monthStartDay = GeneratedColumn<int>(
      'month_start_day', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(1));
  @override
  List<GeneratedColumn> get $columns => [
        id,
        name,
        currency,
        type,
        createdAt,
        syncId,
        myRole,
        memberCount,
        isShared,
        ownerUserId,
        monthStartDay
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'ledgers';
  @override
  VerificationContext validateIntegrity(Insertable<Ledger> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('currency')) {
      context.handle(_currencyMeta,
          currency.isAcceptableOrUnknown(data['currency']!, _currencyMeta));
    }
    if (data.containsKey('type')) {
      context.handle(
          _typeMeta, type.isAcceptableOrUnknown(data['type']!, _typeMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    if (data.containsKey('sync_id')) {
      context.handle(_syncIdMeta,
          syncId.isAcceptableOrUnknown(data['sync_id']!, _syncIdMeta));
    }
    if (data.containsKey('my_role')) {
      context.handle(_myRoleMeta,
          myRole.isAcceptableOrUnknown(data['my_role']!, _myRoleMeta));
    }
    if (data.containsKey('member_count')) {
      context.handle(
          _memberCountMeta,
          memberCount.isAcceptableOrUnknown(
              data['member_count']!, _memberCountMeta));
    }
    if (data.containsKey('is_shared')) {
      context.handle(_isSharedMeta,
          isShared.isAcceptableOrUnknown(data['is_shared']!, _isSharedMeta));
    }
    if (data.containsKey('owner_user_id')) {
      context.handle(
          _ownerUserIdMeta,
          ownerUserId.isAcceptableOrUnknown(
              data['owner_user_id']!, _ownerUserIdMeta));
    }
    if (data.containsKey('month_start_day')) {
      context.handle(
          _monthStartDayMeta,
          monthStartDay.isAcceptableOrUnknown(
              data['month_start_day']!, _monthStartDayMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Ledger map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Ledger(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      currency: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}currency'])!,
      type: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}type'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      syncId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}sync_id']),
      myRole: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}my_role'])!,
      memberCount: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}member_count'])!,
      isShared: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_shared'])!,
      ownerUserId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}owner_user_id']),
      monthStartDay: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}month_start_day'])!,
    );
  }

  @override
  $LedgersTable createAlias(String alias) {
    return $LedgersTable(attachedDatabase, alias);
  }
}

class Ledger extends DataClass implements Insertable<Ledger> {
  final int id;
  final String name;
  final String currency;
  final String type;
  final DateTime createdAt;
  final String? syncId;
  final String myRole;
  final int memberCount;
  final bool isShared;
  final String? ownerUserId;
  final int monthStartDay;
  const Ledger(
      {required this.id,
      required this.name,
      required this.currency,
      required this.type,
      required this.createdAt,
      this.syncId,
      required this.myRole,
      required this.memberCount,
      required this.isShared,
      this.ownerUserId,
      required this.monthStartDay});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['currency'] = Variable<String>(currency);
    map['type'] = Variable<String>(type);
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || syncId != null) {
      map['sync_id'] = Variable<String>(syncId);
    }
    map['my_role'] = Variable<String>(myRole);
    map['member_count'] = Variable<int>(memberCount);
    map['is_shared'] = Variable<bool>(isShared);
    if (!nullToAbsent || ownerUserId != null) {
      map['owner_user_id'] = Variable<String>(ownerUserId);
    }
    map['month_start_day'] = Variable<int>(monthStartDay);
    return map;
  }

  LedgersCompanion toCompanion(bool nullToAbsent) {
    return LedgersCompanion(
      id: Value(id),
      name: Value(name),
      currency: Value(currency),
      type: Value(type),
      createdAt: Value(createdAt),
      syncId:
          syncId == null && nullToAbsent ? const Value.absent() : Value(syncId),
      myRole: Value(myRole),
      memberCount: Value(memberCount),
      isShared: Value(isShared),
      ownerUserId: ownerUserId == null && nullToAbsent
          ? const Value.absent()
          : Value(ownerUserId),
      monthStartDay: Value(monthStartDay),
    );
  }

  factory Ledger.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Ledger(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      currency: serializer.fromJson<String>(json['currency']),
      type: serializer.fromJson<String>(json['type']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      syncId: serializer.fromJson<String?>(json['syncId']),
      myRole: serializer.fromJson<String>(json['myRole']),
      memberCount: serializer.fromJson<int>(json['memberCount']),
      isShared: serializer.fromJson<bool>(json['isShared']),
      ownerUserId: serializer.fromJson<String?>(json['ownerUserId']),
      monthStartDay: serializer.fromJson<int>(json['monthStartDay']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'currency': serializer.toJson<String>(currency),
      'type': serializer.toJson<String>(type),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'syncId': serializer.toJson<String?>(syncId),
      'myRole': serializer.toJson<String>(myRole),
      'memberCount': serializer.toJson<int>(memberCount),
      'isShared': serializer.toJson<bool>(isShared),
      'ownerUserId': serializer.toJson<String?>(ownerUserId),
      'monthStartDay': serializer.toJson<int>(monthStartDay),
    };
  }

  Ledger copyWith(
          {int? id,
          String? name,
          String? currency,
          String? type,
          DateTime? createdAt,
          Value<String?> syncId = const Value.absent(),
          String? myRole,
          int? memberCount,
          bool? isShared,
          Value<String?> ownerUserId = const Value.absent(),
          int? monthStartDay}) =>
      Ledger(
        id: id ?? this.id,
        name: name ?? this.name,
        currency: currency ?? this.currency,
        type: type ?? this.type,
        createdAt: createdAt ?? this.createdAt,
        syncId: syncId.present ? syncId.value : this.syncId,
        myRole: myRole ?? this.myRole,
        memberCount: memberCount ?? this.memberCount,
        isShared: isShared ?? this.isShared,
        ownerUserId: ownerUserId.present ? ownerUserId.value : this.ownerUserId,
        monthStartDay: monthStartDay ?? this.monthStartDay,
      );
  Ledger copyWithCompanion(LedgersCompanion data) {
    return Ledger(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      currency: data.currency.present ? data.currency.value : this.currency,
      type: data.type.present ? data.type.value : this.type,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      syncId: data.syncId.present ? data.syncId.value : this.syncId,
      myRole: data.myRole.present ? data.myRole.value : this.myRole,
      memberCount:
          data.memberCount.present ? data.memberCount.value : this.memberCount,
      isShared: data.isShared.present ? data.isShared.value : this.isShared,
      ownerUserId:
          data.ownerUserId.present ? data.ownerUserId.value : this.ownerUserId,
      monthStartDay: data.monthStartDay.present
          ? data.monthStartDay.value
          : this.monthStartDay,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Ledger(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('currency: $currency, ')
          ..write('type: $type, ')
          ..write('createdAt: $createdAt, ')
          ..write('syncId: $syncId, ')
          ..write('myRole: $myRole, ')
          ..write('memberCount: $memberCount, ')
          ..write('isShared: $isShared, ')
          ..write('ownerUserId: $ownerUserId, ')
          ..write('monthStartDay: $monthStartDay')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, currency, type, createdAt, syncId,
      myRole, memberCount, isShared, ownerUserId, monthStartDay);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Ledger &&
          other.id == this.id &&
          other.name == this.name &&
          other.currency == this.currency &&
          other.type == this.type &&
          other.createdAt == this.createdAt &&
          other.syncId == this.syncId &&
          other.myRole == this.myRole &&
          other.memberCount == this.memberCount &&
          other.isShared == this.isShared &&
          other.ownerUserId == this.ownerUserId &&
          other.monthStartDay == this.monthStartDay);
}

class LedgersCompanion extends UpdateCompanion<Ledger> {
  final Value<int> id;
  final Value<String> name;
  final Value<String> currency;
  final Value<String> type;
  final Value<DateTime> createdAt;
  final Value<String?> syncId;
  final Value<String> myRole;
  final Value<int> memberCount;
  final Value<bool> isShared;
  final Value<String?> ownerUserId;
  final Value<int> monthStartDay;
  const LedgersCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.currency = const Value.absent(),
    this.type = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.syncId = const Value.absent(),
    this.myRole = const Value.absent(),
    this.memberCount = const Value.absent(),
    this.isShared = const Value.absent(),
    this.ownerUserId = const Value.absent(),
    this.monthStartDay = const Value.absent(),
  });
  LedgersCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    this.currency = const Value.absent(),
    this.type = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.syncId = const Value.absent(),
    this.myRole = const Value.absent(),
    this.memberCount = const Value.absent(),
    this.isShared = const Value.absent(),
    this.ownerUserId = const Value.absent(),
    this.monthStartDay = const Value.absent(),
  }) : name = Value(name);
  static Insertable<Ledger> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? currency,
    Expression<String>? type,
    Expression<DateTime>? createdAt,
    Expression<String>? syncId,
    Expression<String>? myRole,
    Expression<int>? memberCount,
    Expression<bool>? isShared,
    Expression<String>? ownerUserId,
    Expression<int>? monthStartDay,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (currency != null) 'currency': currency,
      if (type != null) 'type': type,
      if (createdAt != null) 'created_at': createdAt,
      if (syncId != null) 'sync_id': syncId,
      if (myRole != null) 'my_role': myRole,
      if (memberCount != null) 'member_count': memberCount,
      if (isShared != null) 'is_shared': isShared,
      if (ownerUserId != null) 'owner_user_id': ownerUserId,
      if (monthStartDay != null) 'month_start_day': monthStartDay,
    });
  }

  LedgersCompanion copyWith(
      {Value<int>? id,
      Value<String>? name,
      Value<String>? currency,
      Value<String>? type,
      Value<DateTime>? createdAt,
      Value<String?>? syncId,
      Value<String>? myRole,
      Value<int>? memberCount,
      Value<bool>? isShared,
      Value<String?>? ownerUserId,
      Value<int>? monthStartDay}) {
    return LedgersCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      currency: currency ?? this.currency,
      type: type ?? this.type,
      createdAt: createdAt ?? this.createdAt,
      syncId: syncId ?? this.syncId,
      myRole: myRole ?? this.myRole,
      memberCount: memberCount ?? this.memberCount,
      isShared: isShared ?? this.isShared,
      ownerUserId: ownerUserId ?? this.ownerUserId,
      monthStartDay: monthStartDay ?? this.monthStartDay,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (currency.present) {
      map['currency'] = Variable<String>(currency.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (syncId.present) {
      map['sync_id'] = Variable<String>(syncId.value);
    }
    if (myRole.present) {
      map['my_role'] = Variable<String>(myRole.value);
    }
    if (memberCount.present) {
      map['member_count'] = Variable<int>(memberCount.value);
    }
    if (isShared.present) {
      map['is_shared'] = Variable<bool>(isShared.value);
    }
    if (ownerUserId.present) {
      map['owner_user_id'] = Variable<String>(ownerUserId.value);
    }
    if (monthStartDay.present) {
      map['month_start_day'] = Variable<int>(monthStartDay.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LedgersCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('currency: $currency, ')
          ..write('type: $type, ')
          ..write('createdAt: $createdAt, ')
          ..write('syncId: $syncId, ')
          ..write('myRole: $myRole, ')
          ..write('memberCount: $memberCount, ')
          ..write('isShared: $isShared, ')
          ..write('ownerUserId: $ownerUserId, ')
          ..write('monthStartDay: $monthStartDay')
          ..write(')'))
        .toString();
  }
}

class $AccountsTable extends Accounts with TableInfo<$AccountsTable, Account> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AccountsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _ledgerIdMeta =
      const VerificationMeta('ledgerId');
  @override
  late final GeneratedColumn<int> ledgerId = GeneratedColumn<int>(
      'ledger_id', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
      'type', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('cash'));
  static const VerificationMeta _currencyMeta =
      const VerificationMeta('currency');
  @override
  late final GeneratedColumn<String> currency = GeneratedColumn<String>(
      'currency', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('CNY'));
  static const VerificationMeta _initialBalanceMeta =
      const VerificationMeta('initialBalance');
  @override
  late final GeneratedColumn<double> initialBalance = GeneratedColumn<double>(
      'initial_balance', aliasedName, false,
      type: DriftSqlType.double,
      requiredDuringInsert: false,
      defaultValue: const Constant(0.0));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _sortOrderMeta =
      const VerificationMeta('sortOrder');
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
      'sort_order', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _creditLimitMeta =
      const VerificationMeta('creditLimit');
  @override
  late final GeneratedColumn<double> creditLimit = GeneratedColumn<double>(
      'credit_limit', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _billingDayMeta =
      const VerificationMeta('billingDay');
  @override
  late final GeneratedColumn<int> billingDay = GeneratedColumn<int>(
      'billing_day', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _paymentDueDayMeta =
      const VerificationMeta('paymentDueDay');
  @override
  late final GeneratedColumn<int> paymentDueDay = GeneratedColumn<int>(
      'payment_due_day', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _bankNameMeta =
      const VerificationMeta('bankName');
  @override
  late final GeneratedColumn<String> bankName = GeneratedColumn<String>(
      'bank_name', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _cardLastFourMeta =
      const VerificationMeta('cardLastFour');
  @override
  late final GeneratedColumn<String> cardLastFour = GeneratedColumn<String>(
      'card_last_four', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
      'note', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _syncIdMeta = const VerificationMeta('syncId');
  @override
  late final GeneratedColumn<String> syncId = GeneratedColumn<String>(
      'sync_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _hiddenMeta = const VerificationMeta('hidden');
  @override
  late final GeneratedColumn<bool> hidden = GeneratedColumn<bool>(
      'hidden', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("hidden" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _parentAccountIdMeta =
      const VerificationMeta('parentAccountId');
  @override
  late final GeneratedColumn<String> parentAccountId = GeneratedColumn<String>(
      'parent_account_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _swipesmartCardIdMeta =
      const VerificationMeta('swipesmartCardId');
  @override
  late final GeneratedColumn<String> swipesmartCardId = GeneratedColumn<String>(
      'swipesmart_card_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _avatarPathMeta =
      const VerificationMeta('avatarPath');
  @override
  late final GeneratedColumn<String> avatarPath = GeneratedColumn<String>(
      'avatar_path', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _includeInTotalMeta =
      const VerificationMeta('includeInTotal');
  @override
  late final GeneratedColumn<bool> includeInTotal = GeneratedColumn<bool>(
      'include_in_total', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("include_in_total" IN (0, 1))'),
      defaultValue: const Constant(true));
  @override
  List<GeneratedColumn> get $columns => [
        id,
        ledgerId,
        name,
        type,
        currency,
        initialBalance,
        createdAt,
        updatedAt,
        sortOrder,
        creditLimit,
        billingDay,
        paymentDueDay,
        bankName,
        cardLastFour,
        note,
        syncId,
        hidden,
        parentAccountId,
        swipesmartCardId,
        avatarPath,
        includeInTotal
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'accounts';
  @override
  VerificationContext validateIntegrity(Insertable<Account> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('ledger_id')) {
      context.handle(_ledgerIdMeta,
          ledgerId.isAcceptableOrUnknown(data['ledger_id']!, _ledgerIdMeta));
    } else if (isInserting) {
      context.missing(_ledgerIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
          _typeMeta, type.isAcceptableOrUnknown(data['type']!, _typeMeta));
    }
    if (data.containsKey('currency')) {
      context.handle(_currencyMeta,
          currency.isAcceptableOrUnknown(data['currency']!, _currencyMeta));
    }
    if (data.containsKey('initial_balance')) {
      context.handle(
          _initialBalanceMeta,
          initialBalance.isAcceptableOrUnknown(
              data['initial_balance']!, _initialBalanceMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    }
    if (data.containsKey('sort_order')) {
      context.handle(_sortOrderMeta,
          sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta));
    }
    if (data.containsKey('credit_limit')) {
      context.handle(
          _creditLimitMeta,
          creditLimit.isAcceptableOrUnknown(
              data['credit_limit']!, _creditLimitMeta));
    }
    if (data.containsKey('billing_day')) {
      context.handle(
          _billingDayMeta,
          billingDay.isAcceptableOrUnknown(
              data['billing_day']!, _billingDayMeta));
    }
    if (data.containsKey('payment_due_day')) {
      context.handle(
          _paymentDueDayMeta,
          paymentDueDay.isAcceptableOrUnknown(
              data['payment_due_day']!, _paymentDueDayMeta));
    }
    if (data.containsKey('bank_name')) {
      context.handle(_bankNameMeta,
          bankName.isAcceptableOrUnknown(data['bank_name']!, _bankNameMeta));
    }
    if (data.containsKey('card_last_four')) {
      context.handle(
          _cardLastFourMeta,
          cardLastFour.isAcceptableOrUnknown(
              data['card_last_four']!, _cardLastFourMeta));
    }
    if (data.containsKey('note')) {
      context.handle(
          _noteMeta, note.isAcceptableOrUnknown(data['note']!, _noteMeta));
    }
    if (data.containsKey('sync_id')) {
      context.handle(_syncIdMeta,
          syncId.isAcceptableOrUnknown(data['sync_id']!, _syncIdMeta));
    }
    if (data.containsKey('hidden')) {
      context.handle(_hiddenMeta,
          hidden.isAcceptableOrUnknown(data['hidden']!, _hiddenMeta));
    }
    if (data.containsKey('parent_account_id')) {
      context.handle(
          _parentAccountIdMeta,
          parentAccountId.isAcceptableOrUnknown(
              data['parent_account_id']!, _parentAccountIdMeta));
    }
    if (data.containsKey('swipesmart_card_id')) {
      context.handle(
          _swipesmartCardIdMeta,
          swipesmartCardId.isAcceptableOrUnknown(
              data['swipesmart_card_id']!, _swipesmartCardIdMeta));
    }
    if (data.containsKey('avatar_path')) {
      context.handle(
          _avatarPathMeta,
          avatarPath.isAcceptableOrUnknown(
              data['avatar_path']!, _avatarPathMeta));
    }
    if (data.containsKey('include_in_total')) {
      context.handle(
          _includeInTotalMeta,
          includeInTotal.isAcceptableOrUnknown(
              data['include_in_total']!, _includeInTotalMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Account map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Account(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      ledgerId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}ledger_id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      type: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}type'])!,
      currency: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}currency'])!,
      initialBalance: attachedDatabase.typeMapping.read(
          DriftSqlType.double, data['${effectivePrefix}initial_balance'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at']),
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at']),
      sortOrder: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}sort_order'])!,
      creditLimit: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}credit_limit']),
      billingDay: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}billing_day']),
      paymentDueDay: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}payment_due_day']),
      bankName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}bank_name']),
      cardLastFour: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}card_last_four']),
      note: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}note']),
      syncId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}sync_id']),
      hidden: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}hidden'])!,
      parentAccountId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}parent_account_id']),
      swipesmartCardId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}swipesmart_card_id']),
      avatarPath: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}avatar_path']),
      includeInTotal: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}include_in_total'])!,
    );
  }

  @override
  $AccountsTable createAlias(String alias) {
    return $AccountsTable(attachedDatabase, alias);
  }
}

class Account extends DataClass implements Insertable<Account> {
  final int id;
  final int ledgerId;
  final String name;
  final String type;
  final String currency;
  final double initialBalance;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final int sortOrder;
  final double? creditLimit;
  final int? billingDay;
  final int? paymentDueDay;
  final String? bankName;
  final String? cardLastFour;
  final String? note;
  final String? syncId;

  /// 隐藏:true 时该账户不再出现在记账/转账/周期选择器,账户管理页移入「已隐藏」分区。
  /// 仍计入账户余额、净资产、资产构成、净值趋势(.docs/account-archive/01 §二 D1)。
  final bool hidden;

  /// v32 主帳戶(合併帳單):子卡/附卡指向主卡的 syncId,null = 沒有掛在任何
  /// 主卡下。跟 BeeCount Cloud server `accounts.parent_account_id` 對齊
  /// (docs/MOZE_FEATURE_GAP_SD.md §2.9 Phase 4)。
  final String? parentAccountId;

  /// v47 SwipeSmart 信用卡對照:對應 SwipeSmart 卡片目錄的 cardId,null =
  /// 尚未對照。跟 BeeCount Cloud server `accounts.swipesmart_card_id` 對齊
  /// (docs/superpowers/specs/2026-08-30-swipesmart-integration-design.md §3.1)。
  final String? swipesmartCardId;

  /// v32 帳戶頭像本地相對路徑(如 "custom_icons/<fileId>.png"),跟
  /// Categories.customIconPath 同一套目錄/存取邏輯(CustomIconService)。
  /// 上傳到雲端拿到的 fileId/sha256 不落本地欄位 —— push 時即時上傳算,
  /// 對齊分類自訂圖標的做法(見 entity_serializer.dart serializeCategory)。
  final String? avatarPath;

  /// v43 不納入總餘額(對齊 Moze「balance included」+ BeeCount Cloud
  /// `include_in_total`,正極性、預設 true=納入,避免同步邊界雙重否定)。
  /// 只影響淨資產/資產構成/淨值趨勢等「總額」統計與合併帳單主卡的子卡
  /// 加總 —— 帳戶本身仍正常出現在清單/選擇器,可正常記帳(跟 hidden 是
  /// 兩個獨立維度,見 lib/data/db.dart 的 hidden 註解與
  /// Debts.excludedFromTotal 的先例)。
  final bool includeInTotal;
  const Account(
      {required this.id,
      required this.ledgerId,
      required this.name,
      required this.type,
      required this.currency,
      required this.initialBalance,
      this.createdAt,
      this.updatedAt,
      required this.sortOrder,
      this.creditLimit,
      this.billingDay,
      this.paymentDueDay,
      this.bankName,
      this.cardLastFour,
      this.note,
      this.syncId,
      required this.hidden,
      this.parentAccountId,
      this.swipesmartCardId,
      this.avatarPath,
      required this.includeInTotal});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['ledger_id'] = Variable<int>(ledgerId);
    map['name'] = Variable<String>(name);
    map['type'] = Variable<String>(type);
    map['currency'] = Variable<String>(currency);
    map['initial_balance'] = Variable<double>(initialBalance);
    if (!nullToAbsent || createdAt != null) {
      map['created_at'] = Variable<DateTime>(createdAt);
    }
    if (!nullToAbsent || updatedAt != null) {
      map['updated_at'] = Variable<DateTime>(updatedAt);
    }
    map['sort_order'] = Variable<int>(sortOrder);
    if (!nullToAbsent || creditLimit != null) {
      map['credit_limit'] = Variable<double>(creditLimit);
    }
    if (!nullToAbsent || billingDay != null) {
      map['billing_day'] = Variable<int>(billingDay);
    }
    if (!nullToAbsent || paymentDueDay != null) {
      map['payment_due_day'] = Variable<int>(paymentDueDay);
    }
    if (!nullToAbsent || bankName != null) {
      map['bank_name'] = Variable<String>(bankName);
    }
    if (!nullToAbsent || cardLastFour != null) {
      map['card_last_four'] = Variable<String>(cardLastFour);
    }
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    if (!nullToAbsent || syncId != null) {
      map['sync_id'] = Variable<String>(syncId);
    }
    map['hidden'] = Variable<bool>(hidden);
    if (!nullToAbsent || parentAccountId != null) {
      map['parent_account_id'] = Variable<String>(parentAccountId);
    }
    if (!nullToAbsent || swipesmartCardId != null) {
      map['swipesmart_card_id'] = Variable<String>(swipesmartCardId);
    }
    if (!nullToAbsent || avatarPath != null) {
      map['avatar_path'] = Variable<String>(avatarPath);
    }
    map['include_in_total'] = Variable<bool>(includeInTotal);
    return map;
  }

  AccountsCompanion toCompanion(bool nullToAbsent) {
    return AccountsCompanion(
      id: Value(id),
      ledgerId: Value(ledgerId),
      name: Value(name),
      type: Value(type),
      currency: Value(currency),
      initialBalance: Value(initialBalance),
      createdAt: createdAt == null && nullToAbsent
          ? const Value.absent()
          : Value(createdAt),
      updatedAt: updatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(updatedAt),
      sortOrder: Value(sortOrder),
      creditLimit: creditLimit == null && nullToAbsent
          ? const Value.absent()
          : Value(creditLimit),
      billingDay: billingDay == null && nullToAbsent
          ? const Value.absent()
          : Value(billingDay),
      paymentDueDay: paymentDueDay == null && nullToAbsent
          ? const Value.absent()
          : Value(paymentDueDay),
      bankName: bankName == null && nullToAbsent
          ? const Value.absent()
          : Value(bankName),
      cardLastFour: cardLastFour == null && nullToAbsent
          ? const Value.absent()
          : Value(cardLastFour),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      syncId:
          syncId == null && nullToAbsent ? const Value.absent() : Value(syncId),
      hidden: Value(hidden),
      parentAccountId: parentAccountId == null && nullToAbsent
          ? const Value.absent()
          : Value(parentAccountId),
      swipesmartCardId: swipesmartCardId == null && nullToAbsent
          ? const Value.absent()
          : Value(swipesmartCardId),
      avatarPath: avatarPath == null && nullToAbsent
          ? const Value.absent()
          : Value(avatarPath),
      includeInTotal: Value(includeInTotal),
    );
  }

  factory Account.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Account(
      id: serializer.fromJson<int>(json['id']),
      ledgerId: serializer.fromJson<int>(json['ledgerId']),
      name: serializer.fromJson<String>(json['name']),
      type: serializer.fromJson<String>(json['type']),
      currency: serializer.fromJson<String>(json['currency']),
      initialBalance: serializer.fromJson<double>(json['initialBalance']),
      createdAt: serializer.fromJson<DateTime?>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime?>(json['updatedAt']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      creditLimit: serializer.fromJson<double?>(json['creditLimit']),
      billingDay: serializer.fromJson<int?>(json['billingDay']),
      paymentDueDay: serializer.fromJson<int?>(json['paymentDueDay']),
      bankName: serializer.fromJson<String?>(json['bankName']),
      cardLastFour: serializer.fromJson<String?>(json['cardLastFour']),
      note: serializer.fromJson<String?>(json['note']),
      syncId: serializer.fromJson<String?>(json['syncId']),
      hidden: serializer.fromJson<bool>(json['hidden']),
      parentAccountId: serializer.fromJson<String?>(json['parentAccountId']),
      swipesmartCardId: serializer.fromJson<String?>(json['swipesmartCardId']),
      avatarPath: serializer.fromJson<String?>(json['avatarPath']),
      includeInTotal: serializer.fromJson<bool>(json['includeInTotal']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'ledgerId': serializer.toJson<int>(ledgerId),
      'name': serializer.toJson<String>(name),
      'type': serializer.toJson<String>(type),
      'currency': serializer.toJson<String>(currency),
      'initialBalance': serializer.toJson<double>(initialBalance),
      'createdAt': serializer.toJson<DateTime?>(createdAt),
      'updatedAt': serializer.toJson<DateTime?>(updatedAt),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'creditLimit': serializer.toJson<double?>(creditLimit),
      'billingDay': serializer.toJson<int?>(billingDay),
      'paymentDueDay': serializer.toJson<int?>(paymentDueDay),
      'bankName': serializer.toJson<String?>(bankName),
      'cardLastFour': serializer.toJson<String?>(cardLastFour),
      'note': serializer.toJson<String?>(note),
      'syncId': serializer.toJson<String?>(syncId),
      'hidden': serializer.toJson<bool>(hidden),
      'parentAccountId': serializer.toJson<String?>(parentAccountId),
      'swipesmartCardId': serializer.toJson<String?>(swipesmartCardId),
      'avatarPath': serializer.toJson<String?>(avatarPath),
      'includeInTotal': serializer.toJson<bool>(includeInTotal),
    };
  }

  Account copyWith(
          {int? id,
          int? ledgerId,
          String? name,
          String? type,
          String? currency,
          double? initialBalance,
          Value<DateTime?> createdAt = const Value.absent(),
          Value<DateTime?> updatedAt = const Value.absent(),
          int? sortOrder,
          Value<double?> creditLimit = const Value.absent(),
          Value<int?> billingDay = const Value.absent(),
          Value<int?> paymentDueDay = const Value.absent(),
          Value<String?> bankName = const Value.absent(),
          Value<String?> cardLastFour = const Value.absent(),
          Value<String?> note = const Value.absent(),
          Value<String?> syncId = const Value.absent(),
          bool? hidden,
          Value<String?> parentAccountId = const Value.absent(),
          Value<String?> swipesmartCardId = const Value.absent(),
          Value<String?> avatarPath = const Value.absent(),
          bool? includeInTotal}) =>
      Account(
        id: id ?? this.id,
        ledgerId: ledgerId ?? this.ledgerId,
        name: name ?? this.name,
        type: type ?? this.type,
        currency: currency ?? this.currency,
        initialBalance: initialBalance ?? this.initialBalance,
        createdAt: createdAt.present ? createdAt.value : this.createdAt,
        updatedAt: updatedAt.present ? updatedAt.value : this.updatedAt,
        sortOrder: sortOrder ?? this.sortOrder,
        creditLimit: creditLimit.present ? creditLimit.value : this.creditLimit,
        billingDay: billingDay.present ? billingDay.value : this.billingDay,
        paymentDueDay:
            paymentDueDay.present ? paymentDueDay.value : this.paymentDueDay,
        bankName: bankName.present ? bankName.value : this.bankName,
        cardLastFour:
            cardLastFour.present ? cardLastFour.value : this.cardLastFour,
        note: note.present ? note.value : this.note,
        syncId: syncId.present ? syncId.value : this.syncId,
        hidden: hidden ?? this.hidden,
        parentAccountId: parentAccountId.present
            ? parentAccountId.value
            : this.parentAccountId,
        swipesmartCardId: swipesmartCardId.present
            ? swipesmartCardId.value
            : this.swipesmartCardId,
        avatarPath: avatarPath.present ? avatarPath.value : this.avatarPath,
        includeInTotal: includeInTotal ?? this.includeInTotal,
      );
  Account copyWithCompanion(AccountsCompanion data) {
    return Account(
      id: data.id.present ? data.id.value : this.id,
      ledgerId: data.ledgerId.present ? data.ledgerId.value : this.ledgerId,
      name: data.name.present ? data.name.value : this.name,
      type: data.type.present ? data.type.value : this.type,
      currency: data.currency.present ? data.currency.value : this.currency,
      initialBalance: data.initialBalance.present
          ? data.initialBalance.value
          : this.initialBalance,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      creditLimit:
          data.creditLimit.present ? data.creditLimit.value : this.creditLimit,
      billingDay:
          data.billingDay.present ? data.billingDay.value : this.billingDay,
      paymentDueDay: data.paymentDueDay.present
          ? data.paymentDueDay.value
          : this.paymentDueDay,
      bankName: data.bankName.present ? data.bankName.value : this.bankName,
      cardLastFour: data.cardLastFour.present
          ? data.cardLastFour.value
          : this.cardLastFour,
      note: data.note.present ? data.note.value : this.note,
      syncId: data.syncId.present ? data.syncId.value : this.syncId,
      hidden: data.hidden.present ? data.hidden.value : this.hidden,
      parentAccountId: data.parentAccountId.present
          ? data.parentAccountId.value
          : this.parentAccountId,
      swipesmartCardId: data.swipesmartCardId.present
          ? data.swipesmartCardId.value
          : this.swipesmartCardId,
      avatarPath:
          data.avatarPath.present ? data.avatarPath.value : this.avatarPath,
      includeInTotal: data.includeInTotal.present
          ? data.includeInTotal.value
          : this.includeInTotal,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Account(')
          ..write('id: $id, ')
          ..write('ledgerId: $ledgerId, ')
          ..write('name: $name, ')
          ..write('type: $type, ')
          ..write('currency: $currency, ')
          ..write('initialBalance: $initialBalance, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('creditLimit: $creditLimit, ')
          ..write('billingDay: $billingDay, ')
          ..write('paymentDueDay: $paymentDueDay, ')
          ..write('bankName: $bankName, ')
          ..write('cardLastFour: $cardLastFour, ')
          ..write('note: $note, ')
          ..write('syncId: $syncId, ')
          ..write('hidden: $hidden, ')
          ..write('parentAccountId: $parentAccountId, ')
          ..write('swipesmartCardId: $swipesmartCardId, ')
          ..write('avatarPath: $avatarPath, ')
          ..write('includeInTotal: $includeInTotal')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
        id,
        ledgerId,
        name,
        type,
        currency,
        initialBalance,
        createdAt,
        updatedAt,
        sortOrder,
        creditLimit,
        billingDay,
        paymentDueDay,
        bankName,
        cardLastFour,
        note,
        syncId,
        hidden,
        parentAccountId,
        swipesmartCardId,
        avatarPath,
        includeInTotal
      ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Account &&
          other.id == this.id &&
          other.ledgerId == this.ledgerId &&
          other.name == this.name &&
          other.type == this.type &&
          other.currency == this.currency &&
          other.initialBalance == this.initialBalance &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.sortOrder == this.sortOrder &&
          other.creditLimit == this.creditLimit &&
          other.billingDay == this.billingDay &&
          other.paymentDueDay == this.paymentDueDay &&
          other.bankName == this.bankName &&
          other.cardLastFour == this.cardLastFour &&
          other.note == this.note &&
          other.syncId == this.syncId &&
          other.hidden == this.hidden &&
          other.parentAccountId == this.parentAccountId &&
          other.swipesmartCardId == this.swipesmartCardId &&
          other.avatarPath == this.avatarPath &&
          other.includeInTotal == this.includeInTotal);
}

class AccountsCompanion extends UpdateCompanion<Account> {
  final Value<int> id;
  final Value<int> ledgerId;
  final Value<String> name;
  final Value<String> type;
  final Value<String> currency;
  final Value<double> initialBalance;
  final Value<DateTime?> createdAt;
  final Value<DateTime?> updatedAt;
  final Value<int> sortOrder;
  final Value<double?> creditLimit;
  final Value<int?> billingDay;
  final Value<int?> paymentDueDay;
  final Value<String?> bankName;
  final Value<String?> cardLastFour;
  final Value<String?> note;
  final Value<String?> syncId;
  final Value<bool> hidden;
  final Value<String?> parentAccountId;
  final Value<String?> swipesmartCardId;
  final Value<String?> avatarPath;
  final Value<bool> includeInTotal;
  const AccountsCompanion({
    this.id = const Value.absent(),
    this.ledgerId = const Value.absent(),
    this.name = const Value.absent(),
    this.type = const Value.absent(),
    this.currency = const Value.absent(),
    this.initialBalance = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.creditLimit = const Value.absent(),
    this.billingDay = const Value.absent(),
    this.paymentDueDay = const Value.absent(),
    this.bankName = const Value.absent(),
    this.cardLastFour = const Value.absent(),
    this.note = const Value.absent(),
    this.syncId = const Value.absent(),
    this.hidden = const Value.absent(),
    this.parentAccountId = const Value.absent(),
    this.swipesmartCardId = const Value.absent(),
    this.avatarPath = const Value.absent(),
    this.includeInTotal = const Value.absent(),
  });
  AccountsCompanion.insert({
    this.id = const Value.absent(),
    required int ledgerId,
    required String name,
    this.type = const Value.absent(),
    this.currency = const Value.absent(),
    this.initialBalance = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.creditLimit = const Value.absent(),
    this.billingDay = const Value.absent(),
    this.paymentDueDay = const Value.absent(),
    this.bankName = const Value.absent(),
    this.cardLastFour = const Value.absent(),
    this.note = const Value.absent(),
    this.syncId = const Value.absent(),
    this.hidden = const Value.absent(),
    this.parentAccountId = const Value.absent(),
    this.swipesmartCardId = const Value.absent(),
    this.avatarPath = const Value.absent(),
    this.includeInTotal = const Value.absent(),
  })  : ledgerId = Value(ledgerId),
        name = Value(name);
  static Insertable<Account> custom({
    Expression<int>? id,
    Expression<int>? ledgerId,
    Expression<String>? name,
    Expression<String>? type,
    Expression<String>? currency,
    Expression<double>? initialBalance,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? sortOrder,
    Expression<double>? creditLimit,
    Expression<int>? billingDay,
    Expression<int>? paymentDueDay,
    Expression<String>? bankName,
    Expression<String>? cardLastFour,
    Expression<String>? note,
    Expression<String>? syncId,
    Expression<bool>? hidden,
    Expression<String>? parentAccountId,
    Expression<String>? swipesmartCardId,
    Expression<String>? avatarPath,
    Expression<bool>? includeInTotal,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (ledgerId != null) 'ledger_id': ledgerId,
      if (name != null) 'name': name,
      if (type != null) 'type': type,
      if (currency != null) 'currency': currency,
      if (initialBalance != null) 'initial_balance': initialBalance,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (creditLimit != null) 'credit_limit': creditLimit,
      if (billingDay != null) 'billing_day': billingDay,
      if (paymentDueDay != null) 'payment_due_day': paymentDueDay,
      if (bankName != null) 'bank_name': bankName,
      if (cardLastFour != null) 'card_last_four': cardLastFour,
      if (note != null) 'note': note,
      if (syncId != null) 'sync_id': syncId,
      if (hidden != null) 'hidden': hidden,
      if (parentAccountId != null) 'parent_account_id': parentAccountId,
      if (swipesmartCardId != null) 'swipesmart_card_id': swipesmartCardId,
      if (avatarPath != null) 'avatar_path': avatarPath,
      if (includeInTotal != null) 'include_in_total': includeInTotal,
    });
  }

  AccountsCompanion copyWith(
      {Value<int>? id,
      Value<int>? ledgerId,
      Value<String>? name,
      Value<String>? type,
      Value<String>? currency,
      Value<double>? initialBalance,
      Value<DateTime?>? createdAt,
      Value<DateTime?>? updatedAt,
      Value<int>? sortOrder,
      Value<double?>? creditLimit,
      Value<int?>? billingDay,
      Value<int?>? paymentDueDay,
      Value<String?>? bankName,
      Value<String?>? cardLastFour,
      Value<String?>? note,
      Value<String?>? syncId,
      Value<bool>? hidden,
      Value<String?>? parentAccountId,
      Value<String?>? swipesmartCardId,
      Value<String?>? avatarPath,
      Value<bool>? includeInTotal}) {
    return AccountsCompanion(
      id: id ?? this.id,
      ledgerId: ledgerId ?? this.ledgerId,
      name: name ?? this.name,
      type: type ?? this.type,
      currency: currency ?? this.currency,
      initialBalance: initialBalance ?? this.initialBalance,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      sortOrder: sortOrder ?? this.sortOrder,
      creditLimit: creditLimit ?? this.creditLimit,
      billingDay: billingDay ?? this.billingDay,
      paymentDueDay: paymentDueDay ?? this.paymentDueDay,
      bankName: bankName ?? this.bankName,
      cardLastFour: cardLastFour ?? this.cardLastFour,
      note: note ?? this.note,
      syncId: syncId ?? this.syncId,
      hidden: hidden ?? this.hidden,
      parentAccountId: parentAccountId ?? this.parentAccountId,
      swipesmartCardId: swipesmartCardId ?? this.swipesmartCardId,
      avatarPath: avatarPath ?? this.avatarPath,
      includeInTotal: includeInTotal ?? this.includeInTotal,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (ledgerId.present) {
      map['ledger_id'] = Variable<int>(ledgerId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (currency.present) {
      map['currency'] = Variable<String>(currency.value);
    }
    if (initialBalance.present) {
      map['initial_balance'] = Variable<double>(initialBalance.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (creditLimit.present) {
      map['credit_limit'] = Variable<double>(creditLimit.value);
    }
    if (billingDay.present) {
      map['billing_day'] = Variable<int>(billingDay.value);
    }
    if (paymentDueDay.present) {
      map['payment_due_day'] = Variable<int>(paymentDueDay.value);
    }
    if (bankName.present) {
      map['bank_name'] = Variable<String>(bankName.value);
    }
    if (cardLastFour.present) {
      map['card_last_four'] = Variable<String>(cardLastFour.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (syncId.present) {
      map['sync_id'] = Variable<String>(syncId.value);
    }
    if (hidden.present) {
      map['hidden'] = Variable<bool>(hidden.value);
    }
    if (parentAccountId.present) {
      map['parent_account_id'] = Variable<String>(parentAccountId.value);
    }
    if (swipesmartCardId.present) {
      map['swipesmart_card_id'] = Variable<String>(swipesmartCardId.value);
    }
    if (avatarPath.present) {
      map['avatar_path'] = Variable<String>(avatarPath.value);
    }
    if (includeInTotal.present) {
      map['include_in_total'] = Variable<bool>(includeInTotal.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AccountsCompanion(')
          ..write('id: $id, ')
          ..write('ledgerId: $ledgerId, ')
          ..write('name: $name, ')
          ..write('type: $type, ')
          ..write('currency: $currency, ')
          ..write('initialBalance: $initialBalance, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('creditLimit: $creditLimit, ')
          ..write('billingDay: $billingDay, ')
          ..write('paymentDueDay: $paymentDueDay, ')
          ..write('bankName: $bankName, ')
          ..write('cardLastFour: $cardLastFour, ')
          ..write('note: $note, ')
          ..write('syncId: $syncId, ')
          ..write('hidden: $hidden, ')
          ..write('parentAccountId: $parentAccountId, ')
          ..write('swipesmartCardId: $swipesmartCardId, ')
          ..write('avatarPath: $avatarPath, ')
          ..write('includeInTotal: $includeInTotal')
          ..write(')'))
        .toString();
  }
}

class $CategoriesTable extends Categories
    with TableInfo<$CategoriesTable, Category> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CategoriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
      'kind', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _iconMeta = const VerificationMeta('icon');
  @override
  late final GeneratedColumn<String> icon = GeneratedColumn<String>(
      'icon', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _sortOrderMeta =
      const VerificationMeta('sortOrder');
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
      'sort_order', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _parentIdMeta =
      const VerificationMeta('parentId');
  @override
  late final GeneratedColumn<int> parentId = GeneratedColumn<int>(
      'parent_id', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _levelMeta = const VerificationMeta('level');
  @override
  late final GeneratedColumn<int> level = GeneratedColumn<int>(
      'level', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(1));
  static const VerificationMeta _iconTypeMeta =
      const VerificationMeta('iconType');
  @override
  late final GeneratedColumn<String> iconType = GeneratedColumn<String>(
      'icon_type', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('material'));
  static const VerificationMeta _customIconPathMeta =
      const VerificationMeta('customIconPath');
  @override
  late final GeneratedColumn<String> customIconPath = GeneratedColumn<String>(
      'custom_icon_path', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _communityIconIdMeta =
      const VerificationMeta('communityIconId');
  @override
  late final GeneratedColumn<String> communityIconId = GeneratedColumn<String>(
      'community_icon_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _syncIdMeta = const VerificationMeta('syncId');
  @override
  late final GeneratedColumn<String> syncId = GeneratedColumn<String>(
      'sync_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        name,
        kind,
        icon,
        sortOrder,
        parentId,
        level,
        iconType,
        customIconPath,
        communityIconId,
        syncId
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'categories';
  @override
  VerificationContext validateIntegrity(Insertable<Category> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
          _kindMeta, kind.isAcceptableOrUnknown(data['kind']!, _kindMeta));
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('icon')) {
      context.handle(
          _iconMeta, icon.isAcceptableOrUnknown(data['icon']!, _iconMeta));
    }
    if (data.containsKey('sort_order')) {
      context.handle(_sortOrderMeta,
          sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta));
    }
    if (data.containsKey('parent_id')) {
      context.handle(_parentIdMeta,
          parentId.isAcceptableOrUnknown(data['parent_id']!, _parentIdMeta));
    }
    if (data.containsKey('level')) {
      context.handle(
          _levelMeta, level.isAcceptableOrUnknown(data['level']!, _levelMeta));
    }
    if (data.containsKey('icon_type')) {
      context.handle(_iconTypeMeta,
          iconType.isAcceptableOrUnknown(data['icon_type']!, _iconTypeMeta));
    }
    if (data.containsKey('custom_icon_path')) {
      context.handle(
          _customIconPathMeta,
          customIconPath.isAcceptableOrUnknown(
              data['custom_icon_path']!, _customIconPathMeta));
    }
    if (data.containsKey('community_icon_id')) {
      context.handle(
          _communityIconIdMeta,
          communityIconId.isAcceptableOrUnknown(
              data['community_icon_id']!, _communityIconIdMeta));
    }
    if (data.containsKey('sync_id')) {
      context.handle(_syncIdMeta,
          syncId.isAcceptableOrUnknown(data['sync_id']!, _syncIdMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Category map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Category(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      kind: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}kind'])!,
      icon: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}icon']),
      sortOrder: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}sort_order'])!,
      parentId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}parent_id']),
      level: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}level'])!,
      iconType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}icon_type'])!,
      customIconPath: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}custom_icon_path']),
      communityIconId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}community_icon_id']),
      syncId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}sync_id']),
    );
  }

  @override
  $CategoriesTable createAlias(String alias) {
    return $CategoriesTable(attachedDatabase, alias);
  }
}

class Category extends DataClass implements Insertable<Category> {
  final int id;
  final String name;
  final String kind;
  final String? icon;
  final int sortOrder;
  final int? parentId;
  final int level;
  final String iconType;
  final String? customIconPath;
  final String? communityIconId;
  final String? syncId;
  const Category(
      {required this.id,
      required this.name,
      required this.kind,
      this.icon,
      required this.sortOrder,
      this.parentId,
      required this.level,
      required this.iconType,
      this.customIconPath,
      this.communityIconId,
      this.syncId});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['kind'] = Variable<String>(kind);
    if (!nullToAbsent || icon != null) {
      map['icon'] = Variable<String>(icon);
    }
    map['sort_order'] = Variable<int>(sortOrder);
    if (!nullToAbsent || parentId != null) {
      map['parent_id'] = Variable<int>(parentId);
    }
    map['level'] = Variable<int>(level);
    map['icon_type'] = Variable<String>(iconType);
    if (!nullToAbsent || customIconPath != null) {
      map['custom_icon_path'] = Variable<String>(customIconPath);
    }
    if (!nullToAbsent || communityIconId != null) {
      map['community_icon_id'] = Variable<String>(communityIconId);
    }
    if (!nullToAbsent || syncId != null) {
      map['sync_id'] = Variable<String>(syncId);
    }
    return map;
  }

  CategoriesCompanion toCompanion(bool nullToAbsent) {
    return CategoriesCompanion(
      id: Value(id),
      name: Value(name),
      kind: Value(kind),
      icon: icon == null && nullToAbsent ? const Value.absent() : Value(icon),
      sortOrder: Value(sortOrder),
      parentId: parentId == null && nullToAbsent
          ? const Value.absent()
          : Value(parentId),
      level: Value(level),
      iconType: Value(iconType),
      customIconPath: customIconPath == null && nullToAbsent
          ? const Value.absent()
          : Value(customIconPath),
      communityIconId: communityIconId == null && nullToAbsent
          ? const Value.absent()
          : Value(communityIconId),
      syncId:
          syncId == null && nullToAbsent ? const Value.absent() : Value(syncId),
    );
  }

  factory Category.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Category(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      kind: serializer.fromJson<String>(json['kind']),
      icon: serializer.fromJson<String?>(json['icon']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      parentId: serializer.fromJson<int?>(json['parentId']),
      level: serializer.fromJson<int>(json['level']),
      iconType: serializer.fromJson<String>(json['iconType']),
      customIconPath: serializer.fromJson<String?>(json['customIconPath']),
      communityIconId: serializer.fromJson<String?>(json['communityIconId']),
      syncId: serializer.fromJson<String?>(json['syncId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'kind': serializer.toJson<String>(kind),
      'icon': serializer.toJson<String?>(icon),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'parentId': serializer.toJson<int?>(parentId),
      'level': serializer.toJson<int>(level),
      'iconType': serializer.toJson<String>(iconType),
      'customIconPath': serializer.toJson<String?>(customIconPath),
      'communityIconId': serializer.toJson<String?>(communityIconId),
      'syncId': serializer.toJson<String?>(syncId),
    };
  }

  Category copyWith(
          {int? id,
          String? name,
          String? kind,
          Value<String?> icon = const Value.absent(),
          int? sortOrder,
          Value<int?> parentId = const Value.absent(),
          int? level,
          String? iconType,
          Value<String?> customIconPath = const Value.absent(),
          Value<String?> communityIconId = const Value.absent(),
          Value<String?> syncId = const Value.absent()}) =>
      Category(
        id: id ?? this.id,
        name: name ?? this.name,
        kind: kind ?? this.kind,
        icon: icon.present ? icon.value : this.icon,
        sortOrder: sortOrder ?? this.sortOrder,
        parentId: parentId.present ? parentId.value : this.parentId,
        level: level ?? this.level,
        iconType: iconType ?? this.iconType,
        customIconPath:
            customIconPath.present ? customIconPath.value : this.customIconPath,
        communityIconId: communityIconId.present
            ? communityIconId.value
            : this.communityIconId,
        syncId: syncId.present ? syncId.value : this.syncId,
      );
  Category copyWithCompanion(CategoriesCompanion data) {
    return Category(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      kind: data.kind.present ? data.kind.value : this.kind,
      icon: data.icon.present ? data.icon.value : this.icon,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      parentId: data.parentId.present ? data.parentId.value : this.parentId,
      level: data.level.present ? data.level.value : this.level,
      iconType: data.iconType.present ? data.iconType.value : this.iconType,
      customIconPath: data.customIconPath.present
          ? data.customIconPath.value
          : this.customIconPath,
      communityIconId: data.communityIconId.present
          ? data.communityIconId.value
          : this.communityIconId,
      syncId: data.syncId.present ? data.syncId.value : this.syncId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Category(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('kind: $kind, ')
          ..write('icon: $icon, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('parentId: $parentId, ')
          ..write('level: $level, ')
          ..write('iconType: $iconType, ')
          ..write('customIconPath: $customIconPath, ')
          ..write('communityIconId: $communityIconId, ')
          ..write('syncId: $syncId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, kind, icon, sortOrder, parentId,
      level, iconType, customIconPath, communityIconId, syncId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Category &&
          other.id == this.id &&
          other.name == this.name &&
          other.kind == this.kind &&
          other.icon == this.icon &&
          other.sortOrder == this.sortOrder &&
          other.parentId == this.parentId &&
          other.level == this.level &&
          other.iconType == this.iconType &&
          other.customIconPath == this.customIconPath &&
          other.communityIconId == this.communityIconId &&
          other.syncId == this.syncId);
}

class CategoriesCompanion extends UpdateCompanion<Category> {
  final Value<int> id;
  final Value<String> name;
  final Value<String> kind;
  final Value<String?> icon;
  final Value<int> sortOrder;
  final Value<int?> parentId;
  final Value<int> level;
  final Value<String> iconType;
  final Value<String?> customIconPath;
  final Value<String?> communityIconId;
  final Value<String?> syncId;
  const CategoriesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.kind = const Value.absent(),
    this.icon = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.parentId = const Value.absent(),
    this.level = const Value.absent(),
    this.iconType = const Value.absent(),
    this.customIconPath = const Value.absent(),
    this.communityIconId = const Value.absent(),
    this.syncId = const Value.absent(),
  });
  CategoriesCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    required String kind,
    this.icon = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.parentId = const Value.absent(),
    this.level = const Value.absent(),
    this.iconType = const Value.absent(),
    this.customIconPath = const Value.absent(),
    this.communityIconId = const Value.absent(),
    this.syncId = const Value.absent(),
  })  : name = Value(name),
        kind = Value(kind);
  static Insertable<Category> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? kind,
    Expression<String>? icon,
    Expression<int>? sortOrder,
    Expression<int>? parentId,
    Expression<int>? level,
    Expression<String>? iconType,
    Expression<String>? customIconPath,
    Expression<String>? communityIconId,
    Expression<String>? syncId,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (kind != null) 'kind': kind,
      if (icon != null) 'icon': icon,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (parentId != null) 'parent_id': parentId,
      if (level != null) 'level': level,
      if (iconType != null) 'icon_type': iconType,
      if (customIconPath != null) 'custom_icon_path': customIconPath,
      if (communityIconId != null) 'community_icon_id': communityIconId,
      if (syncId != null) 'sync_id': syncId,
    });
  }

  CategoriesCompanion copyWith(
      {Value<int>? id,
      Value<String>? name,
      Value<String>? kind,
      Value<String?>? icon,
      Value<int>? sortOrder,
      Value<int?>? parentId,
      Value<int>? level,
      Value<String>? iconType,
      Value<String?>? customIconPath,
      Value<String?>? communityIconId,
      Value<String?>? syncId}) {
    return CategoriesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      icon: icon ?? this.icon,
      sortOrder: sortOrder ?? this.sortOrder,
      parentId: parentId ?? this.parentId,
      level: level ?? this.level,
      iconType: iconType ?? this.iconType,
      customIconPath: customIconPath ?? this.customIconPath,
      communityIconId: communityIconId ?? this.communityIconId,
      syncId: syncId ?? this.syncId,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (icon.present) {
      map['icon'] = Variable<String>(icon.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (parentId.present) {
      map['parent_id'] = Variable<int>(parentId.value);
    }
    if (level.present) {
      map['level'] = Variable<int>(level.value);
    }
    if (iconType.present) {
      map['icon_type'] = Variable<String>(iconType.value);
    }
    if (customIconPath.present) {
      map['custom_icon_path'] = Variable<String>(customIconPath.value);
    }
    if (communityIconId.present) {
      map['community_icon_id'] = Variable<String>(communityIconId.value);
    }
    if (syncId.present) {
      map['sync_id'] = Variable<String>(syncId.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CategoriesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('kind: $kind, ')
          ..write('icon: $icon, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('parentId: $parentId, ')
          ..write('level: $level, ')
          ..write('iconType: $iconType, ')
          ..write('customIconPath: $customIconPath, ')
          ..write('communityIconId: $communityIconId, ')
          ..write('syncId: $syncId')
          ..write(')'))
        .toString();
  }
}

class $TransactionsTable extends Transactions
    with TableInfo<$TransactionsTable, Transaction> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TransactionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _ledgerIdMeta =
      const VerificationMeta('ledgerId');
  @override
  late final GeneratedColumn<int> ledgerId = GeneratedColumn<int>(
      'ledger_id', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
      'type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _amountMeta = const VerificationMeta('amount');
  @override
  late final GeneratedColumn<double> amount = GeneratedColumn<double>(
      'amount', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _categoryIdMeta =
      const VerificationMeta('categoryId');
  @override
  late final GeneratedColumn<int> categoryId = GeneratedColumn<int>(
      'category_id', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _accountIdMeta =
      const VerificationMeta('accountId');
  @override
  late final GeneratedColumn<int> accountId = GeneratedColumn<int>(
      'account_id', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _toAccountIdMeta =
      const VerificationMeta('toAccountId');
  @override
  late final GeneratedColumn<int> toAccountId = GeneratedColumn<int>(
      'to_account_id', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _happenedAtMeta =
      const VerificationMeta('happenedAt');
  @override
  late final GeneratedColumn<DateTime> happenedAt = GeneratedColumn<DateTime>(
      'happened_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
      'note', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _syncIdMeta = const VerificationMeta('syncId');
  @override
  late final GeneratedColumn<String> syncId = GeneratedColumn<String>(
      'sync_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _createdByUserIdMeta =
      const VerificationMeta('createdByUserId');
  @override
  late final GeneratedColumn<String> createdByUserId = GeneratedColumn<String>(
      'created_by_user_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _lastEditedByUserIdMeta =
      const VerificationMeta('lastEditedByUserId');
  @override
  late final GeneratedColumn<String> lastEditedByUserId =
      GeneratedColumn<String>('last_edited_by_user_id', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _categorySyncIdOverrideMeta =
      const VerificationMeta('categorySyncIdOverride');
  @override
  late final GeneratedColumn<String> categorySyncIdOverride =
      GeneratedColumn<String>('category_sync_id_override', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _accountSyncIdOverrideMeta =
      const VerificationMeta('accountSyncIdOverride');
  @override
  late final GeneratedColumn<String> accountSyncIdOverride =
      GeneratedColumn<String>('account_sync_id_override', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _toAccountSyncIdOverrideMeta =
      const VerificationMeta('toAccountSyncIdOverride');
  @override
  late final GeneratedColumn<String> toAccountSyncIdOverride =
      GeneratedColumn<String>('to_account_sync_id_override', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _tagSyncIdsOverrideMeta =
      const VerificationMeta('tagSyncIdsOverride');
  @override
  late final GeneratedColumn<String> tagSyncIdsOverride =
      GeneratedColumn<String>('tag_sync_ids_override', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _excludeFromStatsMeta =
      const VerificationMeta('excludeFromStats');
  @override
  late final GeneratedColumn<bool> excludeFromStats = GeneratedColumn<bool>(
      'exclude_from_stats', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("exclude_from_stats" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _excludeFromBudgetMeta =
      const VerificationMeta('excludeFromBudget');
  @override
  late final GeneratedColumn<bool> excludeFromBudget = GeneratedColumn<bool>(
      'exclude_from_budget', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("exclude_from_budget" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _currencyCodeMeta =
      const VerificationMeta('currencyCode');
  @override
  late final GeneratedColumn<String> currencyCode = GeneratedColumn<String>(
      'currency_code', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _nativeAmountMeta =
      const VerificationMeta('nativeAmount');
  @override
  late final GeneratedColumn<double> nativeAmount = GeneratedColumn<double>(
      'native_amount', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _merchantMeta =
      const VerificationMeta('merchant');
  @override
  late final GeneratedColumn<String> merchant = GeneratedColumn<String>(
      'merchant', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _refundOfSyncIdMeta =
      const VerificationMeta('refundOfSyncId');
  @override
  late final GeneratedColumn<String> refundOfSyncId = GeneratedColumn<String>(
      'refund_of_sync_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _rewardRuleIdsJsonMeta =
      const VerificationMeta('rewardRuleIdsJson');
  @override
  late final GeneratedColumn<String> rewardRuleIdsJson =
      GeneratedColumn<String>('reward_rule_ids_json', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _recurringRuleIdMeta =
      const VerificationMeta('recurringRuleId');
  @override
  late final GeneratedColumn<String> recurringRuleId = GeneratedColumn<String>(
      'recurring_rule_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _recurringOccurrenceOverriddenMeta =
      const VerificationMeta('recurringOccurrenceOverridden');
  @override
  late final GeneratedColumn<bool> recurringOccurrenceOverridden =
      GeneratedColumn<bool>(
          'recurring_occurrence_overridden', aliasedName, false,
          type: DriftSqlType.bool,
          requiredDuringInsert: false,
          defaultConstraints: GeneratedColumn.constraintIsAlways(
              'CHECK ("recurring_occurrence_overridden" IN (0, 1))'),
          defaultValue: const Constant(false));
  static const VerificationMeta _reconciledAtMeta =
      const VerificationMeta('reconciledAt');
  @override
  late final GeneratedColumn<DateTime> reconciledAt = GeneratedColumn<DateTime>(
      'reconciled_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _deferredPostingAtMeta =
      const VerificationMeta('deferredPostingAt');
  @override
  late final GeneratedColumn<DateTime> deferredPostingAt =
      GeneratedColumn<DateTime>('deferred_posting_at', aliasedName, true,
          type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _hasSplitsMeta =
      const VerificationMeta('hasSplits');
  @override
  late final GeneratedColumn<bool> hasSplits = GeneratedColumn<bool>(
      'has_splits', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("has_splits" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _debtSyncIdMeta =
      const VerificationMeta('debtSyncId');
  @override
  late final GeneratedColumn<String> debtSyncId = GeneratedColumn<String>(
      'debt_sync_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _toAmountMeta =
      const VerificationMeta('toAmount');
  @override
  late final GeneratedColumn<double> toAmount = GeneratedColumn<double>(
      'to_amount', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _projectSyncIdMeta =
      const VerificationMeta('projectSyncId');
  @override
  late final GeneratedColumn<String> projectSyncId = GeneratedColumn<String>(
      'project_sync_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _needsAccountAssignmentMeta =
      const VerificationMeta('needsAccountAssignment');
  @override
  late final GeneratedColumn<bool> needsAccountAssignment =
      GeneratedColumn<bool>('needs_account_assignment', aliasedName, false,
          type: DriftSqlType.bool,
          requiredDuringInsert: false,
          defaultConstraints: GeneratedColumn.constraintIsAlways(
              'CHECK ("needs_account_assignment" IN (0, 1))'),
          defaultValue: const Constant(false));
  static const VerificationMeta _feeAmountMeta =
      const VerificationMeta('feeAmount');
  @override
  late final GeneratedColumn<double> feeAmount = GeneratedColumn<double>(
      'fee_amount', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _feeLabelMeta =
      const VerificationMeta('feeLabel');
  @override
  late final GeneratedColumn<String> feeLabel = GeneratedColumn<String>(
      'fee_label', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _discountAmountMeta =
      const VerificationMeta('discountAmount');
  @override
  late final GeneratedColumn<double> discountAmount = GeneratedColumn<double>(
      'discount_amount', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _discountLabelMeta =
      const VerificationMeta('discountLabel');
  @override
  late final GeneratedColumn<String> discountLabel = GeneratedColumn<String>(
      'discount_label', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        ledgerId,
        type,
        amount,
        categoryId,
        accountId,
        toAccountId,
        happenedAt,
        note,
        syncId,
        createdByUserId,
        lastEditedByUserId,
        categorySyncIdOverride,
        accountSyncIdOverride,
        toAccountSyncIdOverride,
        tagSyncIdsOverride,
        excludeFromStats,
        excludeFromBudget,
        currencyCode,
        nativeAmount,
        merchant,
        refundOfSyncId,
        rewardRuleIdsJson,
        recurringRuleId,
        recurringOccurrenceOverridden,
        reconciledAt,
        deferredPostingAt,
        hasSplits,
        debtSyncId,
        toAmount,
        projectSyncId,
        needsAccountAssignment,
        feeAmount,
        feeLabel,
        discountAmount,
        discountLabel
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'transactions';
  @override
  VerificationContext validateIntegrity(Insertable<Transaction> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('ledger_id')) {
      context.handle(_ledgerIdMeta,
          ledgerId.isAcceptableOrUnknown(data['ledger_id']!, _ledgerIdMeta));
    } else if (isInserting) {
      context.missing(_ledgerIdMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
          _typeMeta, type.isAcceptableOrUnknown(data['type']!, _typeMeta));
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('amount')) {
      context.handle(_amountMeta,
          amount.isAcceptableOrUnknown(data['amount']!, _amountMeta));
    } else if (isInserting) {
      context.missing(_amountMeta);
    }
    if (data.containsKey('category_id')) {
      context.handle(
          _categoryIdMeta,
          categoryId.isAcceptableOrUnknown(
              data['category_id']!, _categoryIdMeta));
    }
    if (data.containsKey('account_id')) {
      context.handle(_accountIdMeta,
          accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta));
    }
    if (data.containsKey('to_account_id')) {
      context.handle(
          _toAccountIdMeta,
          toAccountId.isAcceptableOrUnknown(
              data['to_account_id']!, _toAccountIdMeta));
    }
    if (data.containsKey('happened_at')) {
      context.handle(
          _happenedAtMeta,
          happenedAt.isAcceptableOrUnknown(
              data['happened_at']!, _happenedAtMeta));
    }
    if (data.containsKey('note')) {
      context.handle(
          _noteMeta, note.isAcceptableOrUnknown(data['note']!, _noteMeta));
    }
    if (data.containsKey('sync_id')) {
      context.handle(_syncIdMeta,
          syncId.isAcceptableOrUnknown(data['sync_id']!, _syncIdMeta));
    }
    if (data.containsKey('created_by_user_id')) {
      context.handle(
          _createdByUserIdMeta,
          createdByUserId.isAcceptableOrUnknown(
              data['created_by_user_id']!, _createdByUserIdMeta));
    }
    if (data.containsKey('last_edited_by_user_id')) {
      context.handle(
          _lastEditedByUserIdMeta,
          lastEditedByUserId.isAcceptableOrUnknown(
              data['last_edited_by_user_id']!, _lastEditedByUserIdMeta));
    }
    if (data.containsKey('category_sync_id_override')) {
      context.handle(
          _categorySyncIdOverrideMeta,
          categorySyncIdOverride.isAcceptableOrUnknown(
              data['category_sync_id_override']!, _categorySyncIdOverrideMeta));
    }
    if (data.containsKey('account_sync_id_override')) {
      context.handle(
          _accountSyncIdOverrideMeta,
          accountSyncIdOverride.isAcceptableOrUnknown(
              data['account_sync_id_override']!, _accountSyncIdOverrideMeta));
    }
    if (data.containsKey('to_account_sync_id_override')) {
      context.handle(
          _toAccountSyncIdOverrideMeta,
          toAccountSyncIdOverride.isAcceptableOrUnknown(
              data['to_account_sync_id_override']!,
              _toAccountSyncIdOverrideMeta));
    }
    if (data.containsKey('tag_sync_ids_override')) {
      context.handle(
          _tagSyncIdsOverrideMeta,
          tagSyncIdsOverride.isAcceptableOrUnknown(
              data['tag_sync_ids_override']!, _tagSyncIdsOverrideMeta));
    }
    if (data.containsKey('exclude_from_stats')) {
      context.handle(
          _excludeFromStatsMeta,
          excludeFromStats.isAcceptableOrUnknown(
              data['exclude_from_stats']!, _excludeFromStatsMeta));
    }
    if (data.containsKey('exclude_from_budget')) {
      context.handle(
          _excludeFromBudgetMeta,
          excludeFromBudget.isAcceptableOrUnknown(
              data['exclude_from_budget']!, _excludeFromBudgetMeta));
    }
    if (data.containsKey('currency_code')) {
      context.handle(
          _currencyCodeMeta,
          currencyCode.isAcceptableOrUnknown(
              data['currency_code']!, _currencyCodeMeta));
    }
    if (data.containsKey('native_amount')) {
      context.handle(
          _nativeAmountMeta,
          nativeAmount.isAcceptableOrUnknown(
              data['native_amount']!, _nativeAmountMeta));
    }
    if (data.containsKey('merchant')) {
      context.handle(_merchantMeta,
          merchant.isAcceptableOrUnknown(data['merchant']!, _merchantMeta));
    }
    if (data.containsKey('refund_of_sync_id')) {
      context.handle(
          _refundOfSyncIdMeta,
          refundOfSyncId.isAcceptableOrUnknown(
              data['refund_of_sync_id']!, _refundOfSyncIdMeta));
    }
    if (data.containsKey('reward_rule_ids_json')) {
      context.handle(
          _rewardRuleIdsJsonMeta,
          rewardRuleIdsJson.isAcceptableOrUnknown(
              data['reward_rule_ids_json']!, _rewardRuleIdsJsonMeta));
    }
    if (data.containsKey('recurring_rule_id')) {
      context.handle(
          _recurringRuleIdMeta,
          recurringRuleId.isAcceptableOrUnknown(
              data['recurring_rule_id']!, _recurringRuleIdMeta));
    }
    if (data.containsKey('recurring_occurrence_overridden')) {
      context.handle(
          _recurringOccurrenceOverriddenMeta,
          recurringOccurrenceOverridden.isAcceptableOrUnknown(
              data['recurring_occurrence_overridden']!,
              _recurringOccurrenceOverriddenMeta));
    }
    if (data.containsKey('reconciled_at')) {
      context.handle(
          _reconciledAtMeta,
          reconciledAt.isAcceptableOrUnknown(
              data['reconciled_at']!, _reconciledAtMeta));
    }
    if (data.containsKey('deferred_posting_at')) {
      context.handle(
          _deferredPostingAtMeta,
          deferredPostingAt.isAcceptableOrUnknown(
              data['deferred_posting_at']!, _deferredPostingAtMeta));
    }
    if (data.containsKey('has_splits')) {
      context.handle(_hasSplitsMeta,
          hasSplits.isAcceptableOrUnknown(data['has_splits']!, _hasSplitsMeta));
    }
    if (data.containsKey('debt_sync_id')) {
      context.handle(
          _debtSyncIdMeta,
          debtSyncId.isAcceptableOrUnknown(
              data['debt_sync_id']!, _debtSyncIdMeta));
    }
    if (data.containsKey('to_amount')) {
      context.handle(_toAmountMeta,
          toAmount.isAcceptableOrUnknown(data['to_amount']!, _toAmountMeta));
    }
    if (data.containsKey('project_sync_id')) {
      context.handle(
          _projectSyncIdMeta,
          projectSyncId.isAcceptableOrUnknown(
              data['project_sync_id']!, _projectSyncIdMeta));
    }
    if (data.containsKey('needs_account_assignment')) {
      context.handle(
          _needsAccountAssignmentMeta,
          needsAccountAssignment.isAcceptableOrUnknown(
              data['needs_account_assignment']!, _needsAccountAssignmentMeta));
    }
    if (data.containsKey('fee_amount')) {
      context.handle(_feeAmountMeta,
          feeAmount.isAcceptableOrUnknown(data['fee_amount']!, _feeAmountMeta));
    }
    if (data.containsKey('fee_label')) {
      context.handle(_feeLabelMeta,
          feeLabel.isAcceptableOrUnknown(data['fee_label']!, _feeLabelMeta));
    }
    if (data.containsKey('discount_amount')) {
      context.handle(
          _discountAmountMeta,
          discountAmount.isAcceptableOrUnknown(
              data['discount_amount']!, _discountAmountMeta));
    }
    if (data.containsKey('discount_label')) {
      context.handle(
          _discountLabelMeta,
          discountLabel.isAcceptableOrUnknown(
              data['discount_label']!, _discountLabelMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Transaction map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Transaction(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      ledgerId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}ledger_id'])!,
      type: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}type'])!,
      amount: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}amount'])!,
      categoryId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}category_id']),
      accountId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}account_id']),
      toAccountId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}to_account_id']),
      happenedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}happened_at'])!,
      note: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}note']),
      syncId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}sync_id']),
      createdByUserId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}created_by_user_id']),
      lastEditedByUserId: attachedDatabase.typeMapping.read(DriftSqlType.string,
          data['${effectivePrefix}last_edited_by_user_id']),
      categorySyncIdOverride: attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}category_sync_id_override']),
      accountSyncIdOverride: attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}account_sync_id_override']),
      toAccountSyncIdOverride: attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}to_account_sync_id_override']),
      tagSyncIdsOverride: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}tag_sync_ids_override']),
      excludeFromStats: attachedDatabase.typeMapping.read(
          DriftSqlType.bool, data['${effectivePrefix}exclude_from_stats'])!,
      excludeFromBudget: attachedDatabase.typeMapping.read(
          DriftSqlType.bool, data['${effectivePrefix}exclude_from_budget'])!,
      currencyCode: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}currency_code']),
      nativeAmount: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}native_amount']),
      merchant: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}merchant']),
      refundOfSyncId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}refund_of_sync_id']),
      rewardRuleIdsJson: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}reward_rule_ids_json']),
      recurringRuleId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}recurring_rule_id']),
      recurringOccurrenceOverridden: attachedDatabase.typeMapping.read(
          DriftSqlType.bool,
          data['${effectivePrefix}recurring_occurrence_overridden'])!,
      reconciledAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}reconciled_at']),
      deferredPostingAt: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}deferred_posting_at']),
      hasSplits: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}has_splits'])!,
      debtSyncId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}debt_sync_id']),
      toAmount: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}to_amount']),
      projectSyncId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}project_sync_id']),
      needsAccountAssignment: attachedDatabase.typeMapping.read(
          DriftSqlType.bool,
          data['${effectivePrefix}needs_account_assignment'])!,
      feeAmount: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}fee_amount']),
      feeLabel: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}fee_label']),
      discountAmount: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}discount_amount']),
      discountLabel: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}discount_label']),
    );
  }

  @override
  $TransactionsTable createAlias(String alias) {
    return $TransactionsTable(attachedDatabase, alias);
  }
}

class Transaction extends DataClass implements Insertable<Transaction> {
  final int id;
  final int ledgerId;
  final String type;
  final double amount;
  final int? categoryId;
  final int? accountId;
  final int? toAccountId;
  final DateTime happenedAt;
  final String? note;
  final String? syncId;
  final String? createdByUserId;
  final String? lastEditedByUserId;
  final String? categorySyncIdOverride;
  final String? accountSyncIdOverride;
  final String? toAccountSyncIdOverride;
  final String? tagSyncIdsOverride;

  /// 不计入收支:true 时从收支统计/图表/月年汇总剔除,但仍计入账户余额、净资产、
  /// 账单列表(.docs/transaction-flags/01 §二 D1)。
  final bool excludeFromStats;

  /// 不计入预算:true 时从预算用量剔除。与 excludeFromStats 完全独立(D2)。
  final bool excludeFromBudget;

  /// v30 交易级多币种(.docs/multi-currency-ledger):交易币种(ISO 大写)。
  /// 有账户 → 恒等于账户 currency(账户内不混币);无账户 → 用户所选(L12,
  /// 默认账本本位币)。显式存让交易自包含(同步/统计不必每次 join 账户)。
  final String? currencyCode;

  /// v30:折算到账本本位币的金额快照(按记账时汇率,保存即定,不随汇率重算)。
  /// 单币种/未折算 == amount(隐含汇率 1.0)。账本维度统计读本列(?? amount),
  /// 账户维度(余额等)仍读 amount。
  final double? nativeAmount;

  /// v33:商家名称。与 note 独立的自由文本字段,BeeCount Cloud 的
  /// read_tx_projection.merchant / _LEDGER_MERGE_SPECS["transaction"] 已支持
  /// 同名 wire 字段 merchant,这里补齐本地列即可直接接上同步。
  final String? merchant;

  /// v34:退款关联——存原交易的 syncId(而非本地 int id,因为本地 id 跨设备不
  /// 稳定)。BeeCount Cloud 服务端已有对应的 refund_of_sync_id 列/业务规则
  /// (一笔交易只能被退一次、退款单不能再被退款),wire 字段名 refundOfId,
  /// 见 sync_applier.py 的 merge spec。
  final String? refundOfSyncId;

  /// v35:信用卡紅利回饋——使用者記帳當下手動勾選的回饋規則 syncId 列表
  /// (JSON list,同 [tagSyncIdsOverride] 那种"JSON list 存 string"写法)。
  /// BeeCount Cloud 端字段是 read_tx_projection.reward_rule_sync_ids_json,
  /// wire 字段名 rewardRuleIds(见 sync_applier.py merge spec)。2026-08-06
  /// 改版后规则不再靠 category_ids 自动比对,这里是权威的"哪笔消费适用哪个
  /// 回馈方案"来源。
  final String? rewardRuleIdsJson;

  /// v36 週期性收支(recurring_rule):这笔交易是哪条規則生成的 occurrence,
  /// 存規則的 **syncId**(不是本地 int id——本地 id 跨装置不稳定,同
  /// [refundOfSyncId] 的模式)。null = 单次交易(非週期生成)。BeeCount Cloud
  /// 端字段是 read_tx_projection.recurring_rule_sync_id,wire 字段名
  /// recurringRuleId,见 sync_applier.py 的 transaction merge spec。
  final String? recurringRuleId;

  /// v36:这期是否被「修改此記錄」单独编辑过——true 时,規則之后的「修改/
  /// 刪除連同未來週期」批次操作要跳过这一笔,不能被批次覆盖。BeeCount Cloud
  /// 端字段是 read_tx_projection.recurring_occurrence_overridden,wire 字段
  /// 名 recurringOccurrenceOverridden。
  final bool recurringOccurrenceOverridden;

  /// v37 對帳模式(§2.10 MOZE_FEATURE_GAP_SD.md,對齊
  /// doc.moze.app/reconciliation/statement-mode):使用者在對帳模式裡勾選
  /// 確認過「這筆交易確實在這期信用卡帳單上」的時間戳。null = 尚未核對。
  /// BeeCount Cloud 端字段是 read_tx_projection.reconciled_at,wire 字段名
  /// reconciledAt(恆發,不是「有值才發」——因為有明確的清空/取消確認動作,
  /// 見 entity_serializer.dart serializeTransaction 的註解)。
  final DateTime? reconciledAt;

  /// v37 延後入帳(對帳模式的必要前置,§2.10):有值 = 這筆交易處於「延後入帳」
  /// 狀態,值是使用者填的實際入帳日;null = 正常,沿用 happenedAt。對帳/信用卡
  /// 帳單彙總等需要「入帳歸屬日」的地方一律用
  /// `lib/utils/reconciliation.dart` 的 `effectiveDate()`(等同 Cloud
  /// `deferred_posting_at ?? happened_at` 的 COALESCE 語意),不要各自重寫。
  /// BeeCount Cloud 端字段是 read_tx_projection.deferred_posting_at,wire
  /// 字段名 deferredPostingAt(同樣恆發)。
  final DateTime? deferredPostingAt;

  /// v38 拆帳(對齊 doc.moze.app/record/split-categories 與 BeeCount Cloud
  /// §2.4 拆分類別):true 時這筆交易的金額拆成多筆分類明細記在
  /// [TransactionSplits],此欄位的 categoryId/categorySyncIdOverride 強制為
  /// null(明細本身才有分類)。BeeCount Cloud 端字段是
  /// read_tx_projection.has_splits,wire 字段名 hasSplits。
  final bool hasSplits;

  /// v39 借還款(對齐 doc.moze.app/record/payables-receivables 與 BeeCount
  /// Cloud debt entity):這筆交易是某個 [Debts] 的一筆還款/收款時,存該欠款
  /// 的 syncId。刻意跟 recurringRuleId 同款存 syncId 字串(不是本地 int
  /// FK)——欠款是 ledger-scoped 實體,本地 int id 跨裝置不保證一致,存
  /// syncId 才能在 pull 尚未把對端新建的欠款同步下來時仍正確引用(對比
  /// categoryId/accountId 那組 user-global 實體需要額外的
  /// *SyncIdOverride 欄位處理共享帳本場景,這裡不需要)。BeeCount Cloud 端
  /// 字段是 read_tx_projection.debt_sync_id,wire 字段名 debtId。恆發
  /// (同 reconciledAt)——清空欠款關聯是明確動作,null 必須能傳達給 server。
  final String? debtSyncId;

  /// v45 跨幣別轉帳(對齐 BeeCount Cloud `to_amount`,alembic
  /// 0044_tx_transfer_to_amount):`type == 'transfer'` 且轉出/轉入帳戶幣別
  /// 不同時,存轉入帳戶自己幣別的金額;同幣別轉帳/非轉帳一律維持 null(不要
  /// 為同幣別轉帳也塞 `toAmount = amount`——`toAmount ?? amount` 這個
  /// COALESCE 慣例才能同時當「轉入金額」跟「是否跨幣別」的單一事實來源)。
  /// BeeCount Cloud 端字段是 read_tx_projection.to_amount,wire 字段名
  /// toAmount(camelCase,對齊 sync_applier.py 的 merge spec)。
  final double? toAmount;

  /// v44 專案(對齐 BeeCount Cloud project sync entity,取代分類預算):這筆
  /// 交易關聯的 [Projects] 的 syncId。跟 [debtSyncId]/[recurringRuleId]
  /// 同款存 syncId 字串(不是本地 int FK)——專案是 ledger-scoped 實體,
  /// 本地 int id 跨裝置不保證一致。BeeCount Cloud 端字段是
  /// read_tx_projection.project_sync_id,wire 字段名 projectId。恆發(同
  /// debtSyncId)——記帳表單「選擇專案」的取消連結是明確動作,必須讓 null
  /// 能傳達給 server。
  final String? projectSyncId;

  /// v40:這筆交易找不到帳戶、且當下沒有 UI 可以攔截使用者選(背景截圖/
  /// 通知監聽、週期性交易產生、CSV 匯入)時,交易仍照常建立(accountId 保持
  /// null,帳戶餘額計算完全不受影響),但打這個旗標讓使用者能在「待確認
  /// 帳戶」列表裡事後補選。有 UI 可攔截的路徑(記帳表單/AI 對話/照片/語音)
  /// 不會用到這個旗標——那些路徑要求使用者當場選,選不了就直接不建立這筆
  /// 交易。
  final bool needsAccountAssignment;

  /// v46 轉帳手續費/折損(對齐 BeeCount Cloud `read_tx_projection.fee_amount`
  /// / `fee_label` / `discount_amount` / `discount_label`,`0039_tx_fee_
  /// discount.py`——Cloud 該組欄位本來就存在,只是原本只放行
  /// expense/income,本次解除 transfer 的硬性拒絕,App/Cloud 直接共用同一組
  /// wire key,不需要新 migration):`type == 'transfer'` 時,`feeAmount` 是
  /// 轉出側額外扣款(轉出帳戶幣別),`discountAmount` 是轉入側到帳前折損
  /// (轉入帳戶幣別)。皆為 null = 沒有手續費/折損,餘額計算退化回原本行為
  /// (見 [LocalAccountRepository] 的 `_transferOutEffect`/
  /// `_transferInEffect`)。**周期性轉帳(`RecurringTransactions`)不支援**,
  /// 範圍比照現有 Web 版 recurring rule 不支援 fee/discount。
  final double? feeAmount;
  final String? feeLabel;
  final double? discountAmount;
  final String? discountLabel;
  const Transaction(
      {required this.id,
      required this.ledgerId,
      required this.type,
      required this.amount,
      this.categoryId,
      this.accountId,
      this.toAccountId,
      required this.happenedAt,
      this.note,
      this.syncId,
      this.createdByUserId,
      this.lastEditedByUserId,
      this.categorySyncIdOverride,
      this.accountSyncIdOverride,
      this.toAccountSyncIdOverride,
      this.tagSyncIdsOverride,
      required this.excludeFromStats,
      required this.excludeFromBudget,
      this.currencyCode,
      this.nativeAmount,
      this.merchant,
      this.refundOfSyncId,
      this.rewardRuleIdsJson,
      this.recurringRuleId,
      required this.recurringOccurrenceOverridden,
      this.reconciledAt,
      this.deferredPostingAt,
      required this.hasSplits,
      this.debtSyncId,
      this.toAmount,
      this.projectSyncId,
      required this.needsAccountAssignment,
      this.feeAmount,
      this.feeLabel,
      this.discountAmount,
      this.discountLabel});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['ledger_id'] = Variable<int>(ledgerId);
    map['type'] = Variable<String>(type);
    map['amount'] = Variable<double>(amount);
    if (!nullToAbsent || categoryId != null) {
      map['category_id'] = Variable<int>(categoryId);
    }
    if (!nullToAbsent || accountId != null) {
      map['account_id'] = Variable<int>(accountId);
    }
    if (!nullToAbsent || toAccountId != null) {
      map['to_account_id'] = Variable<int>(toAccountId);
    }
    map['happened_at'] = Variable<DateTime>(happenedAt);
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    if (!nullToAbsent || syncId != null) {
      map['sync_id'] = Variable<String>(syncId);
    }
    if (!nullToAbsent || createdByUserId != null) {
      map['created_by_user_id'] = Variable<String>(createdByUserId);
    }
    if (!nullToAbsent || lastEditedByUserId != null) {
      map['last_edited_by_user_id'] = Variable<String>(lastEditedByUserId);
    }
    if (!nullToAbsent || categorySyncIdOverride != null) {
      map['category_sync_id_override'] =
          Variable<String>(categorySyncIdOverride);
    }
    if (!nullToAbsent || accountSyncIdOverride != null) {
      map['account_sync_id_override'] = Variable<String>(accountSyncIdOverride);
    }
    if (!nullToAbsent || toAccountSyncIdOverride != null) {
      map['to_account_sync_id_override'] =
          Variable<String>(toAccountSyncIdOverride);
    }
    if (!nullToAbsent || tagSyncIdsOverride != null) {
      map['tag_sync_ids_override'] = Variable<String>(tagSyncIdsOverride);
    }
    map['exclude_from_stats'] = Variable<bool>(excludeFromStats);
    map['exclude_from_budget'] = Variable<bool>(excludeFromBudget);
    if (!nullToAbsent || currencyCode != null) {
      map['currency_code'] = Variable<String>(currencyCode);
    }
    if (!nullToAbsent || nativeAmount != null) {
      map['native_amount'] = Variable<double>(nativeAmount);
    }
    if (!nullToAbsent || merchant != null) {
      map['merchant'] = Variable<String>(merchant);
    }
    if (!nullToAbsent || refundOfSyncId != null) {
      map['refund_of_sync_id'] = Variable<String>(refundOfSyncId);
    }
    if (!nullToAbsent || rewardRuleIdsJson != null) {
      map['reward_rule_ids_json'] = Variable<String>(rewardRuleIdsJson);
    }
    if (!nullToAbsent || recurringRuleId != null) {
      map['recurring_rule_id'] = Variable<String>(recurringRuleId);
    }
    map['recurring_occurrence_overridden'] =
        Variable<bool>(recurringOccurrenceOverridden);
    if (!nullToAbsent || reconciledAt != null) {
      map['reconciled_at'] = Variable<DateTime>(reconciledAt);
    }
    if (!nullToAbsent || deferredPostingAt != null) {
      map['deferred_posting_at'] = Variable<DateTime>(deferredPostingAt);
    }
    map['has_splits'] = Variable<bool>(hasSplits);
    if (!nullToAbsent || debtSyncId != null) {
      map['debt_sync_id'] = Variable<String>(debtSyncId);
    }
    if (!nullToAbsent || toAmount != null) {
      map['to_amount'] = Variable<double>(toAmount);
    }
    if (!nullToAbsent || projectSyncId != null) {
      map['project_sync_id'] = Variable<String>(projectSyncId);
    }
    map['needs_account_assignment'] = Variable<bool>(needsAccountAssignment);
    if (!nullToAbsent || feeAmount != null) {
      map['fee_amount'] = Variable<double>(feeAmount);
    }
    if (!nullToAbsent || feeLabel != null) {
      map['fee_label'] = Variable<String>(feeLabel);
    }
    if (!nullToAbsent || discountAmount != null) {
      map['discount_amount'] = Variable<double>(discountAmount);
    }
    if (!nullToAbsent || discountLabel != null) {
      map['discount_label'] = Variable<String>(discountLabel);
    }
    return map;
  }

  TransactionsCompanion toCompanion(bool nullToAbsent) {
    return TransactionsCompanion(
      id: Value(id),
      ledgerId: Value(ledgerId),
      type: Value(type),
      amount: Value(amount),
      categoryId: categoryId == null && nullToAbsent
          ? const Value.absent()
          : Value(categoryId),
      accountId: accountId == null && nullToAbsent
          ? const Value.absent()
          : Value(accountId),
      toAccountId: toAccountId == null && nullToAbsent
          ? const Value.absent()
          : Value(toAccountId),
      happenedAt: Value(happenedAt),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      syncId:
          syncId == null && nullToAbsent ? const Value.absent() : Value(syncId),
      createdByUserId: createdByUserId == null && nullToAbsent
          ? const Value.absent()
          : Value(createdByUserId),
      lastEditedByUserId: lastEditedByUserId == null && nullToAbsent
          ? const Value.absent()
          : Value(lastEditedByUserId),
      categorySyncIdOverride: categorySyncIdOverride == null && nullToAbsent
          ? const Value.absent()
          : Value(categorySyncIdOverride),
      accountSyncIdOverride: accountSyncIdOverride == null && nullToAbsent
          ? const Value.absent()
          : Value(accountSyncIdOverride),
      toAccountSyncIdOverride: toAccountSyncIdOverride == null && nullToAbsent
          ? const Value.absent()
          : Value(toAccountSyncIdOverride),
      tagSyncIdsOverride: tagSyncIdsOverride == null && nullToAbsent
          ? const Value.absent()
          : Value(tagSyncIdsOverride),
      excludeFromStats: Value(excludeFromStats),
      excludeFromBudget: Value(excludeFromBudget),
      currencyCode: currencyCode == null && nullToAbsent
          ? const Value.absent()
          : Value(currencyCode),
      nativeAmount: nativeAmount == null && nullToAbsent
          ? const Value.absent()
          : Value(nativeAmount),
      merchant: merchant == null && nullToAbsent
          ? const Value.absent()
          : Value(merchant),
      refundOfSyncId: refundOfSyncId == null && nullToAbsent
          ? const Value.absent()
          : Value(refundOfSyncId),
      rewardRuleIdsJson: rewardRuleIdsJson == null && nullToAbsent
          ? const Value.absent()
          : Value(rewardRuleIdsJson),
      recurringRuleId: recurringRuleId == null && nullToAbsent
          ? const Value.absent()
          : Value(recurringRuleId),
      recurringOccurrenceOverridden: Value(recurringOccurrenceOverridden),
      reconciledAt: reconciledAt == null && nullToAbsent
          ? const Value.absent()
          : Value(reconciledAt),
      deferredPostingAt: deferredPostingAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deferredPostingAt),
      hasSplits: Value(hasSplits),
      debtSyncId: debtSyncId == null && nullToAbsent
          ? const Value.absent()
          : Value(debtSyncId),
      toAmount: toAmount == null && nullToAbsent
          ? const Value.absent()
          : Value(toAmount),
      projectSyncId: projectSyncId == null && nullToAbsent
          ? const Value.absent()
          : Value(projectSyncId),
      needsAccountAssignment: Value(needsAccountAssignment),
      feeAmount: feeAmount == null && nullToAbsent
          ? const Value.absent()
          : Value(feeAmount),
      feeLabel: feeLabel == null && nullToAbsent
          ? const Value.absent()
          : Value(feeLabel),
      discountAmount: discountAmount == null && nullToAbsent
          ? const Value.absent()
          : Value(discountAmount),
      discountLabel: discountLabel == null && nullToAbsent
          ? const Value.absent()
          : Value(discountLabel),
    );
  }

  factory Transaction.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Transaction(
      id: serializer.fromJson<int>(json['id']),
      ledgerId: serializer.fromJson<int>(json['ledgerId']),
      type: serializer.fromJson<String>(json['type']),
      amount: serializer.fromJson<double>(json['amount']),
      categoryId: serializer.fromJson<int?>(json['categoryId']),
      accountId: serializer.fromJson<int?>(json['accountId']),
      toAccountId: serializer.fromJson<int?>(json['toAccountId']),
      happenedAt: serializer.fromJson<DateTime>(json['happenedAt']),
      note: serializer.fromJson<String?>(json['note']),
      syncId: serializer.fromJson<String?>(json['syncId']),
      createdByUserId: serializer.fromJson<String?>(json['createdByUserId']),
      lastEditedByUserId:
          serializer.fromJson<String?>(json['lastEditedByUserId']),
      categorySyncIdOverride:
          serializer.fromJson<String?>(json['categorySyncIdOverride']),
      accountSyncIdOverride:
          serializer.fromJson<String?>(json['accountSyncIdOverride']),
      toAccountSyncIdOverride:
          serializer.fromJson<String?>(json['toAccountSyncIdOverride']),
      tagSyncIdsOverride:
          serializer.fromJson<String?>(json['tagSyncIdsOverride']),
      excludeFromStats: serializer.fromJson<bool>(json['excludeFromStats']),
      excludeFromBudget: serializer.fromJson<bool>(json['excludeFromBudget']),
      currencyCode: serializer.fromJson<String?>(json['currencyCode']),
      nativeAmount: serializer.fromJson<double?>(json['nativeAmount']),
      merchant: serializer.fromJson<String?>(json['merchant']),
      refundOfSyncId: serializer.fromJson<String?>(json['refundOfSyncId']),
      rewardRuleIdsJson:
          serializer.fromJson<String?>(json['rewardRuleIdsJson']),
      recurringRuleId: serializer.fromJson<String?>(json['recurringRuleId']),
      recurringOccurrenceOverridden:
          serializer.fromJson<bool>(json['recurringOccurrenceOverridden']),
      reconciledAt: serializer.fromJson<DateTime?>(json['reconciledAt']),
      deferredPostingAt:
          serializer.fromJson<DateTime?>(json['deferredPostingAt']),
      hasSplits: serializer.fromJson<bool>(json['hasSplits']),
      debtSyncId: serializer.fromJson<String?>(json['debtSyncId']),
      toAmount: serializer.fromJson<double?>(json['toAmount']),
      projectSyncId: serializer.fromJson<String?>(json['projectSyncId']),
      needsAccountAssignment:
          serializer.fromJson<bool>(json['needsAccountAssignment']),
      feeAmount: serializer.fromJson<double?>(json['feeAmount']),
      feeLabel: serializer.fromJson<String?>(json['feeLabel']),
      discountAmount: serializer.fromJson<double?>(json['discountAmount']),
      discountLabel: serializer.fromJson<String?>(json['discountLabel']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'ledgerId': serializer.toJson<int>(ledgerId),
      'type': serializer.toJson<String>(type),
      'amount': serializer.toJson<double>(amount),
      'categoryId': serializer.toJson<int?>(categoryId),
      'accountId': serializer.toJson<int?>(accountId),
      'toAccountId': serializer.toJson<int?>(toAccountId),
      'happenedAt': serializer.toJson<DateTime>(happenedAt),
      'note': serializer.toJson<String?>(note),
      'syncId': serializer.toJson<String?>(syncId),
      'createdByUserId': serializer.toJson<String?>(createdByUserId),
      'lastEditedByUserId': serializer.toJson<String?>(lastEditedByUserId),
      'categorySyncIdOverride':
          serializer.toJson<String?>(categorySyncIdOverride),
      'accountSyncIdOverride':
          serializer.toJson<String?>(accountSyncIdOverride),
      'toAccountSyncIdOverride':
          serializer.toJson<String?>(toAccountSyncIdOverride),
      'tagSyncIdsOverride': serializer.toJson<String?>(tagSyncIdsOverride),
      'excludeFromStats': serializer.toJson<bool>(excludeFromStats),
      'excludeFromBudget': serializer.toJson<bool>(excludeFromBudget),
      'currencyCode': serializer.toJson<String?>(currencyCode),
      'nativeAmount': serializer.toJson<double?>(nativeAmount),
      'merchant': serializer.toJson<String?>(merchant),
      'refundOfSyncId': serializer.toJson<String?>(refundOfSyncId),
      'rewardRuleIdsJson': serializer.toJson<String?>(rewardRuleIdsJson),
      'recurringRuleId': serializer.toJson<String?>(recurringRuleId),
      'recurringOccurrenceOverridden':
          serializer.toJson<bool>(recurringOccurrenceOverridden),
      'reconciledAt': serializer.toJson<DateTime?>(reconciledAt),
      'deferredPostingAt': serializer.toJson<DateTime?>(deferredPostingAt),
      'hasSplits': serializer.toJson<bool>(hasSplits),
      'debtSyncId': serializer.toJson<String?>(debtSyncId),
      'toAmount': serializer.toJson<double?>(toAmount),
      'projectSyncId': serializer.toJson<String?>(projectSyncId),
      'needsAccountAssignment': serializer.toJson<bool>(needsAccountAssignment),
      'feeAmount': serializer.toJson<double?>(feeAmount),
      'feeLabel': serializer.toJson<String?>(feeLabel),
      'discountAmount': serializer.toJson<double?>(discountAmount),
      'discountLabel': serializer.toJson<String?>(discountLabel),
    };
  }

  Transaction copyWith(
          {int? id,
          int? ledgerId,
          String? type,
          double? amount,
          Value<int?> categoryId = const Value.absent(),
          Value<int?> accountId = const Value.absent(),
          Value<int?> toAccountId = const Value.absent(),
          DateTime? happenedAt,
          Value<String?> note = const Value.absent(),
          Value<String?> syncId = const Value.absent(),
          Value<String?> createdByUserId = const Value.absent(),
          Value<String?> lastEditedByUserId = const Value.absent(),
          Value<String?> categorySyncIdOverride = const Value.absent(),
          Value<String?> accountSyncIdOverride = const Value.absent(),
          Value<String?> toAccountSyncIdOverride = const Value.absent(),
          Value<String?> tagSyncIdsOverride = const Value.absent(),
          bool? excludeFromStats,
          bool? excludeFromBudget,
          Value<String?> currencyCode = const Value.absent(),
          Value<double?> nativeAmount = const Value.absent(),
          Value<String?> merchant = const Value.absent(),
          Value<String?> refundOfSyncId = const Value.absent(),
          Value<String?> rewardRuleIdsJson = const Value.absent(),
          Value<String?> recurringRuleId = const Value.absent(),
          bool? recurringOccurrenceOverridden,
          Value<DateTime?> reconciledAt = const Value.absent(),
          Value<DateTime?> deferredPostingAt = const Value.absent(),
          bool? hasSplits,
          Value<String?> debtSyncId = const Value.absent(),
          Value<double?> toAmount = const Value.absent(),
          Value<String?> projectSyncId = const Value.absent(),
          bool? needsAccountAssignment,
          Value<double?> feeAmount = const Value.absent(),
          Value<String?> feeLabel = const Value.absent(),
          Value<double?> discountAmount = const Value.absent(),
          Value<String?> discountLabel = const Value.absent()}) =>
      Transaction(
        id: id ?? this.id,
        ledgerId: ledgerId ?? this.ledgerId,
        type: type ?? this.type,
        amount: amount ?? this.amount,
        categoryId: categoryId.present ? categoryId.value : this.categoryId,
        accountId: accountId.present ? accountId.value : this.accountId,
        toAccountId: toAccountId.present ? toAccountId.value : this.toAccountId,
        happenedAt: happenedAt ?? this.happenedAt,
        note: note.present ? note.value : this.note,
        syncId: syncId.present ? syncId.value : this.syncId,
        createdByUserId: createdByUserId.present
            ? createdByUserId.value
            : this.createdByUserId,
        lastEditedByUserId: lastEditedByUserId.present
            ? lastEditedByUserId.value
            : this.lastEditedByUserId,
        categorySyncIdOverride: categorySyncIdOverride.present
            ? categorySyncIdOverride.value
            : this.categorySyncIdOverride,
        accountSyncIdOverride: accountSyncIdOverride.present
            ? accountSyncIdOverride.value
            : this.accountSyncIdOverride,
        toAccountSyncIdOverride: toAccountSyncIdOverride.present
            ? toAccountSyncIdOverride.value
            : this.toAccountSyncIdOverride,
        tagSyncIdsOverride: tagSyncIdsOverride.present
            ? tagSyncIdsOverride.value
            : this.tagSyncIdsOverride,
        excludeFromStats: excludeFromStats ?? this.excludeFromStats,
        excludeFromBudget: excludeFromBudget ?? this.excludeFromBudget,
        currencyCode:
            currencyCode.present ? currencyCode.value : this.currencyCode,
        nativeAmount:
            nativeAmount.present ? nativeAmount.value : this.nativeAmount,
        merchant: merchant.present ? merchant.value : this.merchant,
        refundOfSyncId:
            refundOfSyncId.present ? refundOfSyncId.value : this.refundOfSyncId,
        rewardRuleIdsJson: rewardRuleIdsJson.present
            ? rewardRuleIdsJson.value
            : this.rewardRuleIdsJson,
        recurringRuleId: recurringRuleId.present
            ? recurringRuleId.value
            : this.recurringRuleId,
        recurringOccurrenceOverridden:
            recurringOccurrenceOverridden ?? this.recurringOccurrenceOverridden,
        reconciledAt:
            reconciledAt.present ? reconciledAt.value : this.reconciledAt,
        deferredPostingAt: deferredPostingAt.present
            ? deferredPostingAt.value
            : this.deferredPostingAt,
        hasSplits: hasSplits ?? this.hasSplits,
        debtSyncId: debtSyncId.present ? debtSyncId.value : this.debtSyncId,
        toAmount: toAmount.present ? toAmount.value : this.toAmount,
        projectSyncId:
            projectSyncId.present ? projectSyncId.value : this.projectSyncId,
        needsAccountAssignment:
            needsAccountAssignment ?? this.needsAccountAssignment,
        feeAmount: feeAmount.present ? feeAmount.value : this.feeAmount,
        feeLabel: feeLabel.present ? feeLabel.value : this.feeLabel,
        discountAmount:
            discountAmount.present ? discountAmount.value : this.discountAmount,
        discountLabel:
            discountLabel.present ? discountLabel.value : this.discountLabel,
      );
  Transaction copyWithCompanion(TransactionsCompanion data) {
    return Transaction(
      id: data.id.present ? data.id.value : this.id,
      ledgerId: data.ledgerId.present ? data.ledgerId.value : this.ledgerId,
      type: data.type.present ? data.type.value : this.type,
      amount: data.amount.present ? data.amount.value : this.amount,
      categoryId:
          data.categoryId.present ? data.categoryId.value : this.categoryId,
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      toAccountId:
          data.toAccountId.present ? data.toAccountId.value : this.toAccountId,
      happenedAt:
          data.happenedAt.present ? data.happenedAt.value : this.happenedAt,
      note: data.note.present ? data.note.value : this.note,
      syncId: data.syncId.present ? data.syncId.value : this.syncId,
      createdByUserId: data.createdByUserId.present
          ? data.createdByUserId.value
          : this.createdByUserId,
      lastEditedByUserId: data.lastEditedByUserId.present
          ? data.lastEditedByUserId.value
          : this.lastEditedByUserId,
      categorySyncIdOverride: data.categorySyncIdOverride.present
          ? data.categorySyncIdOverride.value
          : this.categorySyncIdOverride,
      accountSyncIdOverride: data.accountSyncIdOverride.present
          ? data.accountSyncIdOverride.value
          : this.accountSyncIdOverride,
      toAccountSyncIdOverride: data.toAccountSyncIdOverride.present
          ? data.toAccountSyncIdOverride.value
          : this.toAccountSyncIdOverride,
      tagSyncIdsOverride: data.tagSyncIdsOverride.present
          ? data.tagSyncIdsOverride.value
          : this.tagSyncIdsOverride,
      excludeFromStats: data.excludeFromStats.present
          ? data.excludeFromStats.value
          : this.excludeFromStats,
      excludeFromBudget: data.excludeFromBudget.present
          ? data.excludeFromBudget.value
          : this.excludeFromBudget,
      currencyCode: data.currencyCode.present
          ? data.currencyCode.value
          : this.currencyCode,
      nativeAmount: data.nativeAmount.present
          ? data.nativeAmount.value
          : this.nativeAmount,
      merchant: data.merchant.present ? data.merchant.value : this.merchant,
      refundOfSyncId: data.refundOfSyncId.present
          ? data.refundOfSyncId.value
          : this.refundOfSyncId,
      rewardRuleIdsJson: data.rewardRuleIdsJson.present
          ? data.rewardRuleIdsJson.value
          : this.rewardRuleIdsJson,
      recurringRuleId: data.recurringRuleId.present
          ? data.recurringRuleId.value
          : this.recurringRuleId,
      recurringOccurrenceOverridden: data.recurringOccurrenceOverridden.present
          ? data.recurringOccurrenceOverridden.value
          : this.recurringOccurrenceOverridden,
      reconciledAt: data.reconciledAt.present
          ? data.reconciledAt.value
          : this.reconciledAt,
      deferredPostingAt: data.deferredPostingAt.present
          ? data.deferredPostingAt.value
          : this.deferredPostingAt,
      hasSplits: data.hasSplits.present ? data.hasSplits.value : this.hasSplits,
      debtSyncId:
          data.debtSyncId.present ? data.debtSyncId.value : this.debtSyncId,
      toAmount: data.toAmount.present ? data.toAmount.value : this.toAmount,
      projectSyncId: data.projectSyncId.present
          ? data.projectSyncId.value
          : this.projectSyncId,
      needsAccountAssignment: data.needsAccountAssignment.present
          ? data.needsAccountAssignment.value
          : this.needsAccountAssignment,
      feeAmount: data.feeAmount.present ? data.feeAmount.value : this.feeAmount,
      feeLabel: data.feeLabel.present ? data.feeLabel.value : this.feeLabel,
      discountAmount: data.discountAmount.present
          ? data.discountAmount.value
          : this.discountAmount,
      discountLabel: data.discountLabel.present
          ? data.discountLabel.value
          : this.discountLabel,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Transaction(')
          ..write('id: $id, ')
          ..write('ledgerId: $ledgerId, ')
          ..write('type: $type, ')
          ..write('amount: $amount, ')
          ..write('categoryId: $categoryId, ')
          ..write('accountId: $accountId, ')
          ..write('toAccountId: $toAccountId, ')
          ..write('happenedAt: $happenedAt, ')
          ..write('note: $note, ')
          ..write('syncId: $syncId, ')
          ..write('createdByUserId: $createdByUserId, ')
          ..write('lastEditedByUserId: $lastEditedByUserId, ')
          ..write('categorySyncIdOverride: $categorySyncIdOverride, ')
          ..write('accountSyncIdOverride: $accountSyncIdOverride, ')
          ..write('toAccountSyncIdOverride: $toAccountSyncIdOverride, ')
          ..write('tagSyncIdsOverride: $tagSyncIdsOverride, ')
          ..write('excludeFromStats: $excludeFromStats, ')
          ..write('excludeFromBudget: $excludeFromBudget, ')
          ..write('currencyCode: $currencyCode, ')
          ..write('nativeAmount: $nativeAmount, ')
          ..write('merchant: $merchant, ')
          ..write('refundOfSyncId: $refundOfSyncId, ')
          ..write('rewardRuleIdsJson: $rewardRuleIdsJson, ')
          ..write('recurringRuleId: $recurringRuleId, ')
          ..write(
              'recurringOccurrenceOverridden: $recurringOccurrenceOverridden, ')
          ..write('reconciledAt: $reconciledAt, ')
          ..write('deferredPostingAt: $deferredPostingAt, ')
          ..write('hasSplits: $hasSplits, ')
          ..write('debtSyncId: $debtSyncId, ')
          ..write('toAmount: $toAmount, ')
          ..write('projectSyncId: $projectSyncId, ')
          ..write('needsAccountAssignment: $needsAccountAssignment, ')
          ..write('feeAmount: $feeAmount, ')
          ..write('feeLabel: $feeLabel, ')
          ..write('discountAmount: $discountAmount, ')
          ..write('discountLabel: $discountLabel')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
        id,
        ledgerId,
        type,
        amount,
        categoryId,
        accountId,
        toAccountId,
        happenedAt,
        note,
        syncId,
        createdByUserId,
        lastEditedByUserId,
        categorySyncIdOverride,
        accountSyncIdOverride,
        toAccountSyncIdOverride,
        tagSyncIdsOverride,
        excludeFromStats,
        excludeFromBudget,
        currencyCode,
        nativeAmount,
        merchant,
        refundOfSyncId,
        rewardRuleIdsJson,
        recurringRuleId,
        recurringOccurrenceOverridden,
        reconciledAt,
        deferredPostingAt,
        hasSplits,
        debtSyncId,
        toAmount,
        projectSyncId,
        needsAccountAssignment,
        feeAmount,
        feeLabel,
        discountAmount,
        discountLabel
      ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Transaction &&
          other.id == this.id &&
          other.ledgerId == this.ledgerId &&
          other.type == this.type &&
          other.amount == this.amount &&
          other.categoryId == this.categoryId &&
          other.accountId == this.accountId &&
          other.toAccountId == this.toAccountId &&
          other.happenedAt == this.happenedAt &&
          other.note == this.note &&
          other.syncId == this.syncId &&
          other.createdByUserId == this.createdByUserId &&
          other.lastEditedByUserId == this.lastEditedByUserId &&
          other.categorySyncIdOverride == this.categorySyncIdOverride &&
          other.accountSyncIdOverride == this.accountSyncIdOverride &&
          other.toAccountSyncIdOverride == this.toAccountSyncIdOverride &&
          other.tagSyncIdsOverride == this.tagSyncIdsOverride &&
          other.excludeFromStats == this.excludeFromStats &&
          other.excludeFromBudget == this.excludeFromBudget &&
          other.currencyCode == this.currencyCode &&
          other.nativeAmount == this.nativeAmount &&
          other.merchant == this.merchant &&
          other.refundOfSyncId == this.refundOfSyncId &&
          other.rewardRuleIdsJson == this.rewardRuleIdsJson &&
          other.recurringRuleId == this.recurringRuleId &&
          other.recurringOccurrenceOverridden ==
              this.recurringOccurrenceOverridden &&
          other.reconciledAt == this.reconciledAt &&
          other.deferredPostingAt == this.deferredPostingAt &&
          other.hasSplits == this.hasSplits &&
          other.debtSyncId == this.debtSyncId &&
          other.toAmount == this.toAmount &&
          other.projectSyncId == this.projectSyncId &&
          other.needsAccountAssignment == this.needsAccountAssignment &&
          other.feeAmount == this.feeAmount &&
          other.feeLabel == this.feeLabel &&
          other.discountAmount == this.discountAmount &&
          other.discountLabel == this.discountLabel);
}

class TransactionsCompanion extends UpdateCompanion<Transaction> {
  final Value<int> id;
  final Value<int> ledgerId;
  final Value<String> type;
  final Value<double> amount;
  final Value<int?> categoryId;
  final Value<int?> accountId;
  final Value<int?> toAccountId;
  final Value<DateTime> happenedAt;
  final Value<String?> note;
  final Value<String?> syncId;
  final Value<String?> createdByUserId;
  final Value<String?> lastEditedByUserId;
  final Value<String?> categorySyncIdOverride;
  final Value<String?> accountSyncIdOverride;
  final Value<String?> toAccountSyncIdOverride;
  final Value<String?> tagSyncIdsOverride;
  final Value<bool> excludeFromStats;
  final Value<bool> excludeFromBudget;
  final Value<String?> currencyCode;
  final Value<double?> nativeAmount;
  final Value<String?> merchant;
  final Value<String?> refundOfSyncId;
  final Value<String?> rewardRuleIdsJson;
  final Value<String?> recurringRuleId;
  final Value<bool> recurringOccurrenceOverridden;
  final Value<DateTime?> reconciledAt;
  final Value<DateTime?> deferredPostingAt;
  final Value<bool> hasSplits;
  final Value<String?> debtSyncId;
  final Value<double?> toAmount;
  final Value<String?> projectSyncId;
  final Value<bool> needsAccountAssignment;
  final Value<double?> feeAmount;
  final Value<String?> feeLabel;
  final Value<double?> discountAmount;
  final Value<String?> discountLabel;
  const TransactionsCompanion({
    this.id = const Value.absent(),
    this.ledgerId = const Value.absent(),
    this.type = const Value.absent(),
    this.amount = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.accountId = const Value.absent(),
    this.toAccountId = const Value.absent(),
    this.happenedAt = const Value.absent(),
    this.note = const Value.absent(),
    this.syncId = const Value.absent(),
    this.createdByUserId = const Value.absent(),
    this.lastEditedByUserId = const Value.absent(),
    this.categorySyncIdOverride = const Value.absent(),
    this.accountSyncIdOverride = const Value.absent(),
    this.toAccountSyncIdOverride = const Value.absent(),
    this.tagSyncIdsOverride = const Value.absent(),
    this.excludeFromStats = const Value.absent(),
    this.excludeFromBudget = const Value.absent(),
    this.currencyCode = const Value.absent(),
    this.nativeAmount = const Value.absent(),
    this.merchant = const Value.absent(),
    this.refundOfSyncId = const Value.absent(),
    this.rewardRuleIdsJson = const Value.absent(),
    this.recurringRuleId = const Value.absent(),
    this.recurringOccurrenceOverridden = const Value.absent(),
    this.reconciledAt = const Value.absent(),
    this.deferredPostingAt = const Value.absent(),
    this.hasSplits = const Value.absent(),
    this.debtSyncId = const Value.absent(),
    this.toAmount = const Value.absent(),
    this.projectSyncId = const Value.absent(),
    this.needsAccountAssignment = const Value.absent(),
    this.feeAmount = const Value.absent(),
    this.feeLabel = const Value.absent(),
    this.discountAmount = const Value.absent(),
    this.discountLabel = const Value.absent(),
  });
  TransactionsCompanion.insert({
    this.id = const Value.absent(),
    required int ledgerId,
    required String type,
    required double amount,
    this.categoryId = const Value.absent(),
    this.accountId = const Value.absent(),
    this.toAccountId = const Value.absent(),
    this.happenedAt = const Value.absent(),
    this.note = const Value.absent(),
    this.syncId = const Value.absent(),
    this.createdByUserId = const Value.absent(),
    this.lastEditedByUserId = const Value.absent(),
    this.categorySyncIdOverride = const Value.absent(),
    this.accountSyncIdOverride = const Value.absent(),
    this.toAccountSyncIdOverride = const Value.absent(),
    this.tagSyncIdsOverride = const Value.absent(),
    this.excludeFromStats = const Value.absent(),
    this.excludeFromBudget = const Value.absent(),
    this.currencyCode = const Value.absent(),
    this.nativeAmount = const Value.absent(),
    this.merchant = const Value.absent(),
    this.refundOfSyncId = const Value.absent(),
    this.rewardRuleIdsJson = const Value.absent(),
    this.recurringRuleId = const Value.absent(),
    this.recurringOccurrenceOverridden = const Value.absent(),
    this.reconciledAt = const Value.absent(),
    this.deferredPostingAt = const Value.absent(),
    this.hasSplits = const Value.absent(),
    this.debtSyncId = const Value.absent(),
    this.toAmount = const Value.absent(),
    this.projectSyncId = const Value.absent(),
    this.needsAccountAssignment = const Value.absent(),
    this.feeAmount = const Value.absent(),
    this.feeLabel = const Value.absent(),
    this.discountAmount = const Value.absent(),
    this.discountLabel = const Value.absent(),
  })  : ledgerId = Value(ledgerId),
        type = Value(type),
        amount = Value(amount);
  static Insertable<Transaction> custom({
    Expression<int>? id,
    Expression<int>? ledgerId,
    Expression<String>? type,
    Expression<double>? amount,
    Expression<int>? categoryId,
    Expression<int>? accountId,
    Expression<int>? toAccountId,
    Expression<DateTime>? happenedAt,
    Expression<String>? note,
    Expression<String>? syncId,
    Expression<String>? createdByUserId,
    Expression<String>? lastEditedByUserId,
    Expression<String>? categorySyncIdOverride,
    Expression<String>? accountSyncIdOverride,
    Expression<String>? toAccountSyncIdOverride,
    Expression<String>? tagSyncIdsOverride,
    Expression<bool>? excludeFromStats,
    Expression<bool>? excludeFromBudget,
    Expression<String>? currencyCode,
    Expression<double>? nativeAmount,
    Expression<String>? merchant,
    Expression<String>? refundOfSyncId,
    Expression<String>? rewardRuleIdsJson,
    Expression<String>? recurringRuleId,
    Expression<bool>? recurringOccurrenceOverridden,
    Expression<DateTime>? reconciledAt,
    Expression<DateTime>? deferredPostingAt,
    Expression<bool>? hasSplits,
    Expression<String>? debtSyncId,
    Expression<double>? toAmount,
    Expression<String>? projectSyncId,
    Expression<bool>? needsAccountAssignment,
    Expression<double>? feeAmount,
    Expression<String>? feeLabel,
    Expression<double>? discountAmount,
    Expression<String>? discountLabel,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (ledgerId != null) 'ledger_id': ledgerId,
      if (type != null) 'type': type,
      if (amount != null) 'amount': amount,
      if (categoryId != null) 'category_id': categoryId,
      if (accountId != null) 'account_id': accountId,
      if (toAccountId != null) 'to_account_id': toAccountId,
      if (happenedAt != null) 'happened_at': happenedAt,
      if (note != null) 'note': note,
      if (syncId != null) 'sync_id': syncId,
      if (createdByUserId != null) 'created_by_user_id': createdByUserId,
      if (lastEditedByUserId != null)
        'last_edited_by_user_id': lastEditedByUserId,
      if (categorySyncIdOverride != null)
        'category_sync_id_override': categorySyncIdOverride,
      if (accountSyncIdOverride != null)
        'account_sync_id_override': accountSyncIdOverride,
      if (toAccountSyncIdOverride != null)
        'to_account_sync_id_override': toAccountSyncIdOverride,
      if (tagSyncIdsOverride != null)
        'tag_sync_ids_override': tagSyncIdsOverride,
      if (excludeFromStats != null) 'exclude_from_stats': excludeFromStats,
      if (excludeFromBudget != null) 'exclude_from_budget': excludeFromBudget,
      if (currencyCode != null) 'currency_code': currencyCode,
      if (nativeAmount != null) 'native_amount': nativeAmount,
      if (merchant != null) 'merchant': merchant,
      if (refundOfSyncId != null) 'refund_of_sync_id': refundOfSyncId,
      if (rewardRuleIdsJson != null) 'reward_rule_ids_json': rewardRuleIdsJson,
      if (recurringRuleId != null) 'recurring_rule_id': recurringRuleId,
      if (recurringOccurrenceOverridden != null)
        'recurring_occurrence_overridden': recurringOccurrenceOverridden,
      if (reconciledAt != null) 'reconciled_at': reconciledAt,
      if (deferredPostingAt != null) 'deferred_posting_at': deferredPostingAt,
      if (hasSplits != null) 'has_splits': hasSplits,
      if (debtSyncId != null) 'debt_sync_id': debtSyncId,
      if (toAmount != null) 'to_amount': toAmount,
      if (projectSyncId != null) 'project_sync_id': projectSyncId,
      if (needsAccountAssignment != null)
        'needs_account_assignment': needsAccountAssignment,
      if (feeAmount != null) 'fee_amount': feeAmount,
      if (feeLabel != null) 'fee_label': feeLabel,
      if (discountAmount != null) 'discount_amount': discountAmount,
      if (discountLabel != null) 'discount_label': discountLabel,
    });
  }

  TransactionsCompanion copyWith(
      {Value<int>? id,
      Value<int>? ledgerId,
      Value<String>? type,
      Value<double>? amount,
      Value<int?>? categoryId,
      Value<int?>? accountId,
      Value<int?>? toAccountId,
      Value<DateTime>? happenedAt,
      Value<String?>? note,
      Value<String?>? syncId,
      Value<String?>? createdByUserId,
      Value<String?>? lastEditedByUserId,
      Value<String?>? categorySyncIdOverride,
      Value<String?>? accountSyncIdOverride,
      Value<String?>? toAccountSyncIdOverride,
      Value<String?>? tagSyncIdsOverride,
      Value<bool>? excludeFromStats,
      Value<bool>? excludeFromBudget,
      Value<String?>? currencyCode,
      Value<double?>? nativeAmount,
      Value<String?>? merchant,
      Value<String?>? refundOfSyncId,
      Value<String?>? rewardRuleIdsJson,
      Value<String?>? recurringRuleId,
      Value<bool>? recurringOccurrenceOverridden,
      Value<DateTime?>? reconciledAt,
      Value<DateTime?>? deferredPostingAt,
      Value<bool>? hasSplits,
      Value<String?>? debtSyncId,
      Value<double?>? toAmount,
      Value<String?>? projectSyncId,
      Value<bool>? needsAccountAssignment,
      Value<double?>? feeAmount,
      Value<String?>? feeLabel,
      Value<double?>? discountAmount,
      Value<String?>? discountLabel}) {
    return TransactionsCompanion(
      id: id ?? this.id,
      ledgerId: ledgerId ?? this.ledgerId,
      type: type ?? this.type,
      amount: amount ?? this.amount,
      categoryId: categoryId ?? this.categoryId,
      accountId: accountId ?? this.accountId,
      toAccountId: toAccountId ?? this.toAccountId,
      happenedAt: happenedAt ?? this.happenedAt,
      note: note ?? this.note,
      syncId: syncId ?? this.syncId,
      createdByUserId: createdByUserId ?? this.createdByUserId,
      lastEditedByUserId: lastEditedByUserId ?? this.lastEditedByUserId,
      categorySyncIdOverride:
          categorySyncIdOverride ?? this.categorySyncIdOverride,
      accountSyncIdOverride:
          accountSyncIdOverride ?? this.accountSyncIdOverride,
      toAccountSyncIdOverride:
          toAccountSyncIdOverride ?? this.toAccountSyncIdOverride,
      tagSyncIdsOverride: tagSyncIdsOverride ?? this.tagSyncIdsOverride,
      excludeFromStats: excludeFromStats ?? this.excludeFromStats,
      excludeFromBudget: excludeFromBudget ?? this.excludeFromBudget,
      currencyCode: currencyCode ?? this.currencyCode,
      nativeAmount: nativeAmount ?? this.nativeAmount,
      merchant: merchant ?? this.merchant,
      refundOfSyncId: refundOfSyncId ?? this.refundOfSyncId,
      rewardRuleIdsJson: rewardRuleIdsJson ?? this.rewardRuleIdsJson,
      recurringRuleId: recurringRuleId ?? this.recurringRuleId,
      recurringOccurrenceOverridden:
          recurringOccurrenceOverridden ?? this.recurringOccurrenceOverridden,
      reconciledAt: reconciledAt ?? this.reconciledAt,
      deferredPostingAt: deferredPostingAt ?? this.deferredPostingAt,
      hasSplits: hasSplits ?? this.hasSplits,
      debtSyncId: debtSyncId ?? this.debtSyncId,
      toAmount: toAmount ?? this.toAmount,
      projectSyncId: projectSyncId ?? this.projectSyncId,
      needsAccountAssignment:
          needsAccountAssignment ?? this.needsAccountAssignment,
      feeAmount: feeAmount ?? this.feeAmount,
      feeLabel: feeLabel ?? this.feeLabel,
      discountAmount: discountAmount ?? this.discountAmount,
      discountLabel: discountLabel ?? this.discountLabel,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (ledgerId.present) {
      map['ledger_id'] = Variable<int>(ledgerId.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (amount.present) {
      map['amount'] = Variable<double>(amount.value);
    }
    if (categoryId.present) {
      map['category_id'] = Variable<int>(categoryId.value);
    }
    if (accountId.present) {
      map['account_id'] = Variable<int>(accountId.value);
    }
    if (toAccountId.present) {
      map['to_account_id'] = Variable<int>(toAccountId.value);
    }
    if (happenedAt.present) {
      map['happened_at'] = Variable<DateTime>(happenedAt.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (syncId.present) {
      map['sync_id'] = Variable<String>(syncId.value);
    }
    if (createdByUserId.present) {
      map['created_by_user_id'] = Variable<String>(createdByUserId.value);
    }
    if (lastEditedByUserId.present) {
      map['last_edited_by_user_id'] =
          Variable<String>(lastEditedByUserId.value);
    }
    if (categorySyncIdOverride.present) {
      map['category_sync_id_override'] =
          Variable<String>(categorySyncIdOverride.value);
    }
    if (accountSyncIdOverride.present) {
      map['account_sync_id_override'] =
          Variable<String>(accountSyncIdOverride.value);
    }
    if (toAccountSyncIdOverride.present) {
      map['to_account_sync_id_override'] =
          Variable<String>(toAccountSyncIdOverride.value);
    }
    if (tagSyncIdsOverride.present) {
      map['tag_sync_ids_override'] = Variable<String>(tagSyncIdsOverride.value);
    }
    if (excludeFromStats.present) {
      map['exclude_from_stats'] = Variable<bool>(excludeFromStats.value);
    }
    if (excludeFromBudget.present) {
      map['exclude_from_budget'] = Variable<bool>(excludeFromBudget.value);
    }
    if (currencyCode.present) {
      map['currency_code'] = Variable<String>(currencyCode.value);
    }
    if (nativeAmount.present) {
      map['native_amount'] = Variable<double>(nativeAmount.value);
    }
    if (merchant.present) {
      map['merchant'] = Variable<String>(merchant.value);
    }
    if (refundOfSyncId.present) {
      map['refund_of_sync_id'] = Variable<String>(refundOfSyncId.value);
    }
    if (rewardRuleIdsJson.present) {
      map['reward_rule_ids_json'] = Variable<String>(rewardRuleIdsJson.value);
    }
    if (recurringRuleId.present) {
      map['recurring_rule_id'] = Variable<String>(recurringRuleId.value);
    }
    if (recurringOccurrenceOverridden.present) {
      map['recurring_occurrence_overridden'] =
          Variable<bool>(recurringOccurrenceOverridden.value);
    }
    if (reconciledAt.present) {
      map['reconciled_at'] = Variable<DateTime>(reconciledAt.value);
    }
    if (deferredPostingAt.present) {
      map['deferred_posting_at'] = Variable<DateTime>(deferredPostingAt.value);
    }
    if (hasSplits.present) {
      map['has_splits'] = Variable<bool>(hasSplits.value);
    }
    if (debtSyncId.present) {
      map['debt_sync_id'] = Variable<String>(debtSyncId.value);
    }
    if (toAmount.present) {
      map['to_amount'] = Variable<double>(toAmount.value);
    }
    if (projectSyncId.present) {
      map['project_sync_id'] = Variable<String>(projectSyncId.value);
    }
    if (needsAccountAssignment.present) {
      map['needs_account_assignment'] =
          Variable<bool>(needsAccountAssignment.value);
    }
    if (feeAmount.present) {
      map['fee_amount'] = Variable<double>(feeAmount.value);
    }
    if (feeLabel.present) {
      map['fee_label'] = Variable<String>(feeLabel.value);
    }
    if (discountAmount.present) {
      map['discount_amount'] = Variable<double>(discountAmount.value);
    }
    if (discountLabel.present) {
      map['discount_label'] = Variable<String>(discountLabel.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TransactionsCompanion(')
          ..write('id: $id, ')
          ..write('ledgerId: $ledgerId, ')
          ..write('type: $type, ')
          ..write('amount: $amount, ')
          ..write('categoryId: $categoryId, ')
          ..write('accountId: $accountId, ')
          ..write('toAccountId: $toAccountId, ')
          ..write('happenedAt: $happenedAt, ')
          ..write('note: $note, ')
          ..write('syncId: $syncId, ')
          ..write('createdByUserId: $createdByUserId, ')
          ..write('lastEditedByUserId: $lastEditedByUserId, ')
          ..write('categorySyncIdOverride: $categorySyncIdOverride, ')
          ..write('accountSyncIdOverride: $accountSyncIdOverride, ')
          ..write('toAccountSyncIdOverride: $toAccountSyncIdOverride, ')
          ..write('tagSyncIdsOverride: $tagSyncIdsOverride, ')
          ..write('excludeFromStats: $excludeFromStats, ')
          ..write('excludeFromBudget: $excludeFromBudget, ')
          ..write('currencyCode: $currencyCode, ')
          ..write('nativeAmount: $nativeAmount, ')
          ..write('merchant: $merchant, ')
          ..write('refundOfSyncId: $refundOfSyncId, ')
          ..write('rewardRuleIdsJson: $rewardRuleIdsJson, ')
          ..write('recurringRuleId: $recurringRuleId, ')
          ..write(
              'recurringOccurrenceOverridden: $recurringOccurrenceOverridden, ')
          ..write('reconciledAt: $reconciledAt, ')
          ..write('deferredPostingAt: $deferredPostingAt, ')
          ..write('hasSplits: $hasSplits, ')
          ..write('debtSyncId: $debtSyncId, ')
          ..write('toAmount: $toAmount, ')
          ..write('projectSyncId: $projectSyncId, ')
          ..write('needsAccountAssignment: $needsAccountAssignment, ')
          ..write('feeAmount: $feeAmount, ')
          ..write('feeLabel: $feeLabel, ')
          ..write('discountAmount: $discountAmount, ')
          ..write('discountLabel: $discountLabel')
          ..write(')'))
        .toString();
  }
}

class $RecurringTransactionsTable extends RecurringTransactions
    with TableInfo<$RecurringTransactionsTable, RecurringTransaction> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RecurringTransactionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _syncIdMeta = const VerificationMeta('syncId');
  @override
  late final GeneratedColumn<String> syncId = GeneratedColumn<String>(
      'sync_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _ledgerIdMeta =
      const VerificationMeta('ledgerId');
  @override
  late final GeneratedColumn<int> ledgerId = GeneratedColumn<int>(
      'ledger_id', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
      'type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _amountMeta = const VerificationMeta('amount');
  @override
  late final GeneratedColumn<double> amount = GeneratedColumn<double>(
      'amount', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _categoryIdMeta =
      const VerificationMeta('categoryId');
  @override
  late final GeneratedColumn<int> categoryId = GeneratedColumn<int>(
      'category_id', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _accountIdMeta =
      const VerificationMeta('accountId');
  @override
  late final GeneratedColumn<int> accountId = GeneratedColumn<int>(
      'account_id', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _fromAccountIdMeta =
      const VerificationMeta('fromAccountId');
  @override
  late final GeneratedColumn<int> fromAccountId = GeneratedColumn<int>(
      'from_account_id', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _toAccountIdMeta =
      const VerificationMeta('toAccountId');
  @override
  late final GeneratedColumn<int> toAccountId = GeneratedColumn<int>(
      'to_account_id', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
      'note', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _merchantMeta =
      const VerificationMeta('merchant');
  @override
  late final GeneratedColumn<String> merchant = GeneratedColumn<String>(
      'merchant', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _tagSyncIdsJsonMeta =
      const VerificationMeta('tagSyncIdsJson');
  @override
  late final GeneratedColumn<String> tagSyncIdsJson = GeneratedColumn<String>(
      'tag_sync_ids_json', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _rewardRuleIdsJsonMeta =
      const VerificationMeta('rewardRuleIdsJson');
  @override
  late final GeneratedColumn<String> rewardRuleIdsJson =
      GeneratedColumn<String>('reward_rule_ids_json', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _frequencyMeta =
      const VerificationMeta('frequency');
  @override
  late final GeneratedColumn<String> frequency = GeneratedColumn<String>(
      'frequency', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _intervalMeta =
      const VerificationMeta('interval');
  @override
  late final GeneratedColumn<int> interval = GeneratedColumn<int>(
      'interval', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(1));
  static const VerificationMeta _advancedRuleJsonMeta =
      const VerificationMeta('advancedRuleJson');
  @override
  late final GeneratedColumn<String> advancedRuleJson = GeneratedColumn<String>(
      'advanced_rule_json', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _nextRunAtMeta =
      const VerificationMeta('nextRunAt');
  @override
  late final GeneratedColumn<DateTime> nextRunAt = GeneratedColumn<DateTime>(
      'next_run_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _endAtMeta = const VerificationMeta('endAt');
  @override
  late final GeneratedColumn<DateTime> endAt = GeneratedColumn<DateTime>(
      'end_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _generatedUntilAtMeta =
      const VerificationMeta('generatedUntilAt');
  @override
  late final GeneratedColumn<DateTime> generatedUntilAt =
      GeneratedColumn<DateTime>('generated_until_at', aliasedName, true,
          type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _enabledMeta =
      const VerificationMeta('enabled');
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
      'enabled', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("enabled" IN (0, 1))'),
      defaultValue: const Constant(true));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        syncId,
        ledgerId,
        type,
        amount,
        categoryId,
        accountId,
        fromAccountId,
        toAccountId,
        note,
        merchant,
        tagSyncIdsJson,
        rewardRuleIdsJson,
        frequency,
        interval,
        advancedRuleJson,
        nextRunAt,
        endAt,
        generatedUntilAt,
        enabled,
        createdAt,
        updatedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'recurring_transactions';
  @override
  VerificationContext validateIntegrity(
      Insertable<RecurringTransaction> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('sync_id')) {
      context.handle(_syncIdMeta,
          syncId.isAcceptableOrUnknown(data['sync_id']!, _syncIdMeta));
    }
    if (data.containsKey('ledger_id')) {
      context.handle(_ledgerIdMeta,
          ledgerId.isAcceptableOrUnknown(data['ledger_id']!, _ledgerIdMeta));
    } else if (isInserting) {
      context.missing(_ledgerIdMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
          _typeMeta, type.isAcceptableOrUnknown(data['type']!, _typeMeta));
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('amount')) {
      context.handle(_amountMeta,
          amount.isAcceptableOrUnknown(data['amount']!, _amountMeta));
    } else if (isInserting) {
      context.missing(_amountMeta);
    }
    if (data.containsKey('category_id')) {
      context.handle(
          _categoryIdMeta,
          categoryId.isAcceptableOrUnknown(
              data['category_id']!, _categoryIdMeta));
    }
    if (data.containsKey('account_id')) {
      context.handle(_accountIdMeta,
          accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta));
    }
    if (data.containsKey('from_account_id')) {
      context.handle(
          _fromAccountIdMeta,
          fromAccountId.isAcceptableOrUnknown(
              data['from_account_id']!, _fromAccountIdMeta));
    }
    if (data.containsKey('to_account_id')) {
      context.handle(
          _toAccountIdMeta,
          toAccountId.isAcceptableOrUnknown(
              data['to_account_id']!, _toAccountIdMeta));
    }
    if (data.containsKey('note')) {
      context.handle(
          _noteMeta, note.isAcceptableOrUnknown(data['note']!, _noteMeta));
    }
    if (data.containsKey('merchant')) {
      context.handle(_merchantMeta,
          merchant.isAcceptableOrUnknown(data['merchant']!, _merchantMeta));
    }
    if (data.containsKey('tag_sync_ids_json')) {
      context.handle(
          _tagSyncIdsJsonMeta,
          tagSyncIdsJson.isAcceptableOrUnknown(
              data['tag_sync_ids_json']!, _tagSyncIdsJsonMeta));
    }
    if (data.containsKey('reward_rule_ids_json')) {
      context.handle(
          _rewardRuleIdsJsonMeta,
          rewardRuleIdsJson.isAcceptableOrUnknown(
              data['reward_rule_ids_json']!, _rewardRuleIdsJsonMeta));
    }
    if (data.containsKey('frequency')) {
      context.handle(_frequencyMeta,
          frequency.isAcceptableOrUnknown(data['frequency']!, _frequencyMeta));
    } else if (isInserting) {
      context.missing(_frequencyMeta);
    }
    if (data.containsKey('interval')) {
      context.handle(_intervalMeta,
          interval.isAcceptableOrUnknown(data['interval']!, _intervalMeta));
    }
    if (data.containsKey('advanced_rule_json')) {
      context.handle(
          _advancedRuleJsonMeta,
          advancedRuleJson.isAcceptableOrUnknown(
              data['advanced_rule_json']!, _advancedRuleJsonMeta));
    }
    if (data.containsKey('next_run_at')) {
      context.handle(
          _nextRunAtMeta,
          nextRunAt.isAcceptableOrUnknown(
              data['next_run_at']!, _nextRunAtMeta));
    } else if (isInserting) {
      context.missing(_nextRunAtMeta);
    }
    if (data.containsKey('end_at')) {
      context.handle(
          _endAtMeta, endAt.isAcceptableOrUnknown(data['end_at']!, _endAtMeta));
    }
    if (data.containsKey('generated_until_at')) {
      context.handle(
          _generatedUntilAtMeta,
          generatedUntilAt.isAcceptableOrUnknown(
              data['generated_until_at']!, _generatedUntilAtMeta));
    }
    if (data.containsKey('enabled')) {
      context.handle(_enabledMeta,
          enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  RecurringTransaction map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RecurringTransaction(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      syncId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}sync_id']),
      ledgerId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}ledger_id'])!,
      type: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}type'])!,
      amount: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}amount'])!,
      categoryId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}category_id']),
      accountId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}account_id']),
      fromAccountId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}from_account_id']),
      toAccountId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}to_account_id']),
      note: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}note']),
      merchant: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}merchant']),
      tagSyncIdsJson: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}tag_sync_ids_json']),
      rewardRuleIdsJson: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}reward_rule_ids_json']),
      frequency: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}frequency'])!,
      interval: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}interval'])!,
      advancedRuleJson: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}advanced_rule_json']),
      nextRunAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}next_run_at'])!,
      endAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}end_at']),
      generatedUntilAt: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}generated_until_at']),
      enabled: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}enabled'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $RecurringTransactionsTable createAlias(String alias) {
    return $RecurringTransactionsTable(attachedDatabase, alias);
  }
}

class RecurringTransaction extends DataClass
    implements Insertable<RecurringTransaction> {
  final int id;

  /// 跨设备同步 syncId(UUID)。本地建规则时就地产生(同 transaction/account
  /// 的产生时机),不等 server 回传。
  final String? syncId;
  final int ledgerId;
  final String type;
  final double amount;
  final int? categoryId;
  final int? accountId;

  /// 轉帳來源帳戶。跟 Cloud `recurring_rule` 一样把 accountId(收支用)跟
  /// fromAccountId(转帐来源)分开存,不像 [Transactions] 表本身转账时借用
  /// accountId 当来源——這張規則表序列化/反序列化时要各自对应正确的 key。
  final int? fromAccountId;
  final int? toAccountId;
  final String? note;

  /// 商家名称,同 [Transaction.merchant] 语意,规则生成的每期 occurrence 都
  /// 继承这个值。wire 字段 merchant。
  final String? merchant;

  /// JSON list of tag syncId,规则生成的每期 occurrence 都带上这些标签。
  /// wire 字段 tagIds,同 [TransactionRewardRuleIds] 那种"JSON list 存
  /// string"写法,配 [RecurringTransactionTagIds] extension 用。
  final String? tagSyncIdsJson;

  /// JSON list of card_reward_rule syncId,同 [Transaction.rewardRuleIdsJson]
  /// 语意,规则生成的每期 occurrence 都带上。wire 字段 rewardRuleIds。
  final String? rewardRuleIdsJson;
  final String frequency;
  final int interval;

  /// 進階規則(JSON),只支援兩種、不過度泛化,对齐 Cloud
  /// `services/recurring_schedule.py` 的 `advanced_rule`:
  /// - `{"type":"weekly_days","days":[0,6]}`:每週指定星期几(Dart
  ///   `DateTime.weekday` 惯例转换过的 Monday=0..Sunday=6,注意**跟 Dart
  ///   原生 `weekday`(Monday=1..Sunday=7)不同**,存取都要过一层转换,不要
  ///   直接拿 `DateTime.weekday` 存进来)。
  /// - `{"type":"monthly_day","day":10}`:每隔 interval 个月的第 N 天,超过
  ///   当月天数会夹断到月底。
  /// null = 不用進階規則,单纯"每 interval 个 frequency"重复(如"每2周")。
  /// wire 字段 advancedRuleJson。
  final String? advancedRuleJson;

  /// 規則定義的循环起点(建规则当下就固定,之后不会被续产生逻辑推进——同
  /// Cloud `recurring_rule.next_run_at` 语意)。取代旧版 `startDate`。
  final DateTime nextRunAt;

  /// 為空表示無限期。取代旧版 `endDate`(改名对齐 wire 字段 endAt)。
  final DateTime? endAt;

  /// 已經生成到哪个时间点(視窗批次预生成的进度指标)。取代旧版
  /// "最后一次生成交易的日期"(`lastGeneratedDate`)语意上从"上次生成
  /// 日"变成"已生成到哪"——续产生逻辑靠这个欄位判断要不要补窗口。wire 字段
  /// generatedUntilAt。
  final DateTime? generatedUntilAt;
  final bool enabled;
  final DateTime createdAt;
  final DateTime updatedAt;
  const RecurringTransaction(
      {required this.id,
      this.syncId,
      required this.ledgerId,
      required this.type,
      required this.amount,
      this.categoryId,
      this.accountId,
      this.fromAccountId,
      this.toAccountId,
      this.note,
      this.merchant,
      this.tagSyncIdsJson,
      this.rewardRuleIdsJson,
      required this.frequency,
      required this.interval,
      this.advancedRuleJson,
      required this.nextRunAt,
      this.endAt,
      this.generatedUntilAt,
      required this.enabled,
      required this.createdAt,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || syncId != null) {
      map['sync_id'] = Variable<String>(syncId);
    }
    map['ledger_id'] = Variable<int>(ledgerId);
    map['type'] = Variable<String>(type);
    map['amount'] = Variable<double>(amount);
    if (!nullToAbsent || categoryId != null) {
      map['category_id'] = Variable<int>(categoryId);
    }
    if (!nullToAbsent || accountId != null) {
      map['account_id'] = Variable<int>(accountId);
    }
    if (!nullToAbsent || fromAccountId != null) {
      map['from_account_id'] = Variable<int>(fromAccountId);
    }
    if (!nullToAbsent || toAccountId != null) {
      map['to_account_id'] = Variable<int>(toAccountId);
    }
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    if (!nullToAbsent || merchant != null) {
      map['merchant'] = Variable<String>(merchant);
    }
    if (!nullToAbsent || tagSyncIdsJson != null) {
      map['tag_sync_ids_json'] = Variable<String>(tagSyncIdsJson);
    }
    if (!nullToAbsent || rewardRuleIdsJson != null) {
      map['reward_rule_ids_json'] = Variable<String>(rewardRuleIdsJson);
    }
    map['frequency'] = Variable<String>(frequency);
    map['interval'] = Variable<int>(interval);
    if (!nullToAbsent || advancedRuleJson != null) {
      map['advanced_rule_json'] = Variable<String>(advancedRuleJson);
    }
    map['next_run_at'] = Variable<DateTime>(nextRunAt);
    if (!nullToAbsent || endAt != null) {
      map['end_at'] = Variable<DateTime>(endAt);
    }
    if (!nullToAbsent || generatedUntilAt != null) {
      map['generated_until_at'] = Variable<DateTime>(generatedUntilAt);
    }
    map['enabled'] = Variable<bool>(enabled);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  RecurringTransactionsCompanion toCompanion(bool nullToAbsent) {
    return RecurringTransactionsCompanion(
      id: Value(id),
      syncId:
          syncId == null && nullToAbsent ? const Value.absent() : Value(syncId),
      ledgerId: Value(ledgerId),
      type: Value(type),
      amount: Value(amount),
      categoryId: categoryId == null && nullToAbsent
          ? const Value.absent()
          : Value(categoryId),
      accountId: accountId == null && nullToAbsent
          ? const Value.absent()
          : Value(accountId),
      fromAccountId: fromAccountId == null && nullToAbsent
          ? const Value.absent()
          : Value(fromAccountId),
      toAccountId: toAccountId == null && nullToAbsent
          ? const Value.absent()
          : Value(toAccountId),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      merchant: merchant == null && nullToAbsent
          ? const Value.absent()
          : Value(merchant),
      tagSyncIdsJson: tagSyncIdsJson == null && nullToAbsent
          ? const Value.absent()
          : Value(tagSyncIdsJson),
      rewardRuleIdsJson: rewardRuleIdsJson == null && nullToAbsent
          ? const Value.absent()
          : Value(rewardRuleIdsJson),
      frequency: Value(frequency),
      interval: Value(interval),
      advancedRuleJson: advancedRuleJson == null && nullToAbsent
          ? const Value.absent()
          : Value(advancedRuleJson),
      nextRunAt: Value(nextRunAt),
      endAt:
          endAt == null && nullToAbsent ? const Value.absent() : Value(endAt),
      generatedUntilAt: generatedUntilAt == null && nullToAbsent
          ? const Value.absent()
          : Value(generatedUntilAt),
      enabled: Value(enabled),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory RecurringTransaction.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RecurringTransaction(
      id: serializer.fromJson<int>(json['id']),
      syncId: serializer.fromJson<String?>(json['syncId']),
      ledgerId: serializer.fromJson<int>(json['ledgerId']),
      type: serializer.fromJson<String>(json['type']),
      amount: serializer.fromJson<double>(json['amount']),
      categoryId: serializer.fromJson<int?>(json['categoryId']),
      accountId: serializer.fromJson<int?>(json['accountId']),
      fromAccountId: serializer.fromJson<int?>(json['fromAccountId']),
      toAccountId: serializer.fromJson<int?>(json['toAccountId']),
      note: serializer.fromJson<String?>(json['note']),
      merchant: serializer.fromJson<String?>(json['merchant']),
      tagSyncIdsJson: serializer.fromJson<String?>(json['tagSyncIdsJson']),
      rewardRuleIdsJson:
          serializer.fromJson<String?>(json['rewardRuleIdsJson']),
      frequency: serializer.fromJson<String>(json['frequency']),
      interval: serializer.fromJson<int>(json['interval']),
      advancedRuleJson: serializer.fromJson<String?>(json['advancedRuleJson']),
      nextRunAt: serializer.fromJson<DateTime>(json['nextRunAt']),
      endAt: serializer.fromJson<DateTime?>(json['endAt']),
      generatedUntilAt:
          serializer.fromJson<DateTime?>(json['generatedUntilAt']),
      enabled: serializer.fromJson<bool>(json['enabled']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'syncId': serializer.toJson<String?>(syncId),
      'ledgerId': serializer.toJson<int>(ledgerId),
      'type': serializer.toJson<String>(type),
      'amount': serializer.toJson<double>(amount),
      'categoryId': serializer.toJson<int?>(categoryId),
      'accountId': serializer.toJson<int?>(accountId),
      'fromAccountId': serializer.toJson<int?>(fromAccountId),
      'toAccountId': serializer.toJson<int?>(toAccountId),
      'note': serializer.toJson<String?>(note),
      'merchant': serializer.toJson<String?>(merchant),
      'tagSyncIdsJson': serializer.toJson<String?>(tagSyncIdsJson),
      'rewardRuleIdsJson': serializer.toJson<String?>(rewardRuleIdsJson),
      'frequency': serializer.toJson<String>(frequency),
      'interval': serializer.toJson<int>(interval),
      'advancedRuleJson': serializer.toJson<String?>(advancedRuleJson),
      'nextRunAt': serializer.toJson<DateTime>(nextRunAt),
      'endAt': serializer.toJson<DateTime?>(endAt),
      'generatedUntilAt': serializer.toJson<DateTime?>(generatedUntilAt),
      'enabled': serializer.toJson<bool>(enabled),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  RecurringTransaction copyWith(
          {int? id,
          Value<String?> syncId = const Value.absent(),
          int? ledgerId,
          String? type,
          double? amount,
          Value<int?> categoryId = const Value.absent(),
          Value<int?> accountId = const Value.absent(),
          Value<int?> fromAccountId = const Value.absent(),
          Value<int?> toAccountId = const Value.absent(),
          Value<String?> note = const Value.absent(),
          Value<String?> merchant = const Value.absent(),
          Value<String?> tagSyncIdsJson = const Value.absent(),
          Value<String?> rewardRuleIdsJson = const Value.absent(),
          String? frequency,
          int? interval,
          Value<String?> advancedRuleJson = const Value.absent(),
          DateTime? nextRunAt,
          Value<DateTime?> endAt = const Value.absent(),
          Value<DateTime?> generatedUntilAt = const Value.absent(),
          bool? enabled,
          DateTime? createdAt,
          DateTime? updatedAt}) =>
      RecurringTransaction(
        id: id ?? this.id,
        syncId: syncId.present ? syncId.value : this.syncId,
        ledgerId: ledgerId ?? this.ledgerId,
        type: type ?? this.type,
        amount: amount ?? this.amount,
        categoryId: categoryId.present ? categoryId.value : this.categoryId,
        accountId: accountId.present ? accountId.value : this.accountId,
        fromAccountId:
            fromAccountId.present ? fromAccountId.value : this.fromAccountId,
        toAccountId: toAccountId.present ? toAccountId.value : this.toAccountId,
        note: note.present ? note.value : this.note,
        merchant: merchant.present ? merchant.value : this.merchant,
        tagSyncIdsJson:
            tagSyncIdsJson.present ? tagSyncIdsJson.value : this.tagSyncIdsJson,
        rewardRuleIdsJson: rewardRuleIdsJson.present
            ? rewardRuleIdsJson.value
            : this.rewardRuleIdsJson,
        frequency: frequency ?? this.frequency,
        interval: interval ?? this.interval,
        advancedRuleJson: advancedRuleJson.present
            ? advancedRuleJson.value
            : this.advancedRuleJson,
        nextRunAt: nextRunAt ?? this.nextRunAt,
        endAt: endAt.present ? endAt.value : this.endAt,
        generatedUntilAt: generatedUntilAt.present
            ? generatedUntilAt.value
            : this.generatedUntilAt,
        enabled: enabled ?? this.enabled,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  RecurringTransaction copyWithCompanion(RecurringTransactionsCompanion data) {
    return RecurringTransaction(
      id: data.id.present ? data.id.value : this.id,
      syncId: data.syncId.present ? data.syncId.value : this.syncId,
      ledgerId: data.ledgerId.present ? data.ledgerId.value : this.ledgerId,
      type: data.type.present ? data.type.value : this.type,
      amount: data.amount.present ? data.amount.value : this.amount,
      categoryId:
          data.categoryId.present ? data.categoryId.value : this.categoryId,
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      fromAccountId: data.fromAccountId.present
          ? data.fromAccountId.value
          : this.fromAccountId,
      toAccountId:
          data.toAccountId.present ? data.toAccountId.value : this.toAccountId,
      note: data.note.present ? data.note.value : this.note,
      merchant: data.merchant.present ? data.merchant.value : this.merchant,
      tagSyncIdsJson: data.tagSyncIdsJson.present
          ? data.tagSyncIdsJson.value
          : this.tagSyncIdsJson,
      rewardRuleIdsJson: data.rewardRuleIdsJson.present
          ? data.rewardRuleIdsJson.value
          : this.rewardRuleIdsJson,
      frequency: data.frequency.present ? data.frequency.value : this.frequency,
      interval: data.interval.present ? data.interval.value : this.interval,
      advancedRuleJson: data.advancedRuleJson.present
          ? data.advancedRuleJson.value
          : this.advancedRuleJson,
      nextRunAt: data.nextRunAt.present ? data.nextRunAt.value : this.nextRunAt,
      endAt: data.endAt.present ? data.endAt.value : this.endAt,
      generatedUntilAt: data.generatedUntilAt.present
          ? data.generatedUntilAt.value
          : this.generatedUntilAt,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RecurringTransaction(')
          ..write('id: $id, ')
          ..write('syncId: $syncId, ')
          ..write('ledgerId: $ledgerId, ')
          ..write('type: $type, ')
          ..write('amount: $amount, ')
          ..write('categoryId: $categoryId, ')
          ..write('accountId: $accountId, ')
          ..write('fromAccountId: $fromAccountId, ')
          ..write('toAccountId: $toAccountId, ')
          ..write('note: $note, ')
          ..write('merchant: $merchant, ')
          ..write('tagSyncIdsJson: $tagSyncIdsJson, ')
          ..write('rewardRuleIdsJson: $rewardRuleIdsJson, ')
          ..write('frequency: $frequency, ')
          ..write('interval: $interval, ')
          ..write('advancedRuleJson: $advancedRuleJson, ')
          ..write('nextRunAt: $nextRunAt, ')
          ..write('endAt: $endAt, ')
          ..write('generatedUntilAt: $generatedUntilAt, ')
          ..write('enabled: $enabled, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
        id,
        syncId,
        ledgerId,
        type,
        amount,
        categoryId,
        accountId,
        fromAccountId,
        toAccountId,
        note,
        merchant,
        tagSyncIdsJson,
        rewardRuleIdsJson,
        frequency,
        interval,
        advancedRuleJson,
        nextRunAt,
        endAt,
        generatedUntilAt,
        enabled,
        createdAt,
        updatedAt
      ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RecurringTransaction &&
          other.id == this.id &&
          other.syncId == this.syncId &&
          other.ledgerId == this.ledgerId &&
          other.type == this.type &&
          other.amount == this.amount &&
          other.categoryId == this.categoryId &&
          other.accountId == this.accountId &&
          other.fromAccountId == this.fromAccountId &&
          other.toAccountId == this.toAccountId &&
          other.note == this.note &&
          other.merchant == this.merchant &&
          other.tagSyncIdsJson == this.tagSyncIdsJson &&
          other.rewardRuleIdsJson == this.rewardRuleIdsJson &&
          other.frequency == this.frequency &&
          other.interval == this.interval &&
          other.advancedRuleJson == this.advancedRuleJson &&
          other.nextRunAt == this.nextRunAt &&
          other.endAt == this.endAt &&
          other.generatedUntilAt == this.generatedUntilAt &&
          other.enabled == this.enabled &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class RecurringTransactionsCompanion
    extends UpdateCompanion<RecurringTransaction> {
  final Value<int> id;
  final Value<String?> syncId;
  final Value<int> ledgerId;
  final Value<String> type;
  final Value<double> amount;
  final Value<int?> categoryId;
  final Value<int?> accountId;
  final Value<int?> fromAccountId;
  final Value<int?> toAccountId;
  final Value<String?> note;
  final Value<String?> merchant;
  final Value<String?> tagSyncIdsJson;
  final Value<String?> rewardRuleIdsJson;
  final Value<String> frequency;
  final Value<int> interval;
  final Value<String?> advancedRuleJson;
  final Value<DateTime> nextRunAt;
  final Value<DateTime?> endAt;
  final Value<DateTime?> generatedUntilAt;
  final Value<bool> enabled;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  const RecurringTransactionsCompanion({
    this.id = const Value.absent(),
    this.syncId = const Value.absent(),
    this.ledgerId = const Value.absent(),
    this.type = const Value.absent(),
    this.amount = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.accountId = const Value.absent(),
    this.fromAccountId = const Value.absent(),
    this.toAccountId = const Value.absent(),
    this.note = const Value.absent(),
    this.merchant = const Value.absent(),
    this.tagSyncIdsJson = const Value.absent(),
    this.rewardRuleIdsJson = const Value.absent(),
    this.frequency = const Value.absent(),
    this.interval = const Value.absent(),
    this.advancedRuleJson = const Value.absent(),
    this.nextRunAt = const Value.absent(),
    this.endAt = const Value.absent(),
    this.generatedUntilAt = const Value.absent(),
    this.enabled = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  RecurringTransactionsCompanion.insert({
    this.id = const Value.absent(),
    this.syncId = const Value.absent(),
    required int ledgerId,
    required String type,
    required double amount,
    this.categoryId = const Value.absent(),
    this.accountId = const Value.absent(),
    this.fromAccountId = const Value.absent(),
    this.toAccountId = const Value.absent(),
    this.note = const Value.absent(),
    this.merchant = const Value.absent(),
    this.tagSyncIdsJson = const Value.absent(),
    this.rewardRuleIdsJson = const Value.absent(),
    required String frequency,
    this.interval = const Value.absent(),
    this.advancedRuleJson = const Value.absent(),
    required DateTime nextRunAt,
    this.endAt = const Value.absent(),
    this.generatedUntilAt = const Value.absent(),
    this.enabled = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  })  : ledgerId = Value(ledgerId),
        type = Value(type),
        amount = Value(amount),
        frequency = Value(frequency),
        nextRunAt = Value(nextRunAt);
  static Insertable<RecurringTransaction> custom({
    Expression<int>? id,
    Expression<String>? syncId,
    Expression<int>? ledgerId,
    Expression<String>? type,
    Expression<double>? amount,
    Expression<int>? categoryId,
    Expression<int>? accountId,
    Expression<int>? fromAccountId,
    Expression<int>? toAccountId,
    Expression<String>? note,
    Expression<String>? merchant,
    Expression<String>? tagSyncIdsJson,
    Expression<String>? rewardRuleIdsJson,
    Expression<String>? frequency,
    Expression<int>? interval,
    Expression<String>? advancedRuleJson,
    Expression<DateTime>? nextRunAt,
    Expression<DateTime>? endAt,
    Expression<DateTime>? generatedUntilAt,
    Expression<bool>? enabled,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (syncId != null) 'sync_id': syncId,
      if (ledgerId != null) 'ledger_id': ledgerId,
      if (type != null) 'type': type,
      if (amount != null) 'amount': amount,
      if (categoryId != null) 'category_id': categoryId,
      if (accountId != null) 'account_id': accountId,
      if (fromAccountId != null) 'from_account_id': fromAccountId,
      if (toAccountId != null) 'to_account_id': toAccountId,
      if (note != null) 'note': note,
      if (merchant != null) 'merchant': merchant,
      if (tagSyncIdsJson != null) 'tag_sync_ids_json': tagSyncIdsJson,
      if (rewardRuleIdsJson != null) 'reward_rule_ids_json': rewardRuleIdsJson,
      if (frequency != null) 'frequency': frequency,
      if (interval != null) 'interval': interval,
      if (advancedRuleJson != null) 'advanced_rule_json': advancedRuleJson,
      if (nextRunAt != null) 'next_run_at': nextRunAt,
      if (endAt != null) 'end_at': endAt,
      if (generatedUntilAt != null) 'generated_until_at': generatedUntilAt,
      if (enabled != null) 'enabled': enabled,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  RecurringTransactionsCompanion copyWith(
      {Value<int>? id,
      Value<String?>? syncId,
      Value<int>? ledgerId,
      Value<String>? type,
      Value<double>? amount,
      Value<int?>? categoryId,
      Value<int?>? accountId,
      Value<int?>? fromAccountId,
      Value<int?>? toAccountId,
      Value<String?>? note,
      Value<String?>? merchant,
      Value<String?>? tagSyncIdsJson,
      Value<String?>? rewardRuleIdsJson,
      Value<String>? frequency,
      Value<int>? interval,
      Value<String?>? advancedRuleJson,
      Value<DateTime>? nextRunAt,
      Value<DateTime?>? endAt,
      Value<DateTime?>? generatedUntilAt,
      Value<bool>? enabled,
      Value<DateTime>? createdAt,
      Value<DateTime>? updatedAt}) {
    return RecurringTransactionsCompanion(
      id: id ?? this.id,
      syncId: syncId ?? this.syncId,
      ledgerId: ledgerId ?? this.ledgerId,
      type: type ?? this.type,
      amount: amount ?? this.amount,
      categoryId: categoryId ?? this.categoryId,
      accountId: accountId ?? this.accountId,
      fromAccountId: fromAccountId ?? this.fromAccountId,
      toAccountId: toAccountId ?? this.toAccountId,
      note: note ?? this.note,
      merchant: merchant ?? this.merchant,
      tagSyncIdsJson: tagSyncIdsJson ?? this.tagSyncIdsJson,
      rewardRuleIdsJson: rewardRuleIdsJson ?? this.rewardRuleIdsJson,
      frequency: frequency ?? this.frequency,
      interval: interval ?? this.interval,
      advancedRuleJson: advancedRuleJson ?? this.advancedRuleJson,
      nextRunAt: nextRunAt ?? this.nextRunAt,
      endAt: endAt ?? this.endAt,
      generatedUntilAt: generatedUntilAt ?? this.generatedUntilAt,
      enabled: enabled ?? this.enabled,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (syncId.present) {
      map['sync_id'] = Variable<String>(syncId.value);
    }
    if (ledgerId.present) {
      map['ledger_id'] = Variable<int>(ledgerId.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (amount.present) {
      map['amount'] = Variable<double>(amount.value);
    }
    if (categoryId.present) {
      map['category_id'] = Variable<int>(categoryId.value);
    }
    if (accountId.present) {
      map['account_id'] = Variable<int>(accountId.value);
    }
    if (fromAccountId.present) {
      map['from_account_id'] = Variable<int>(fromAccountId.value);
    }
    if (toAccountId.present) {
      map['to_account_id'] = Variable<int>(toAccountId.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (merchant.present) {
      map['merchant'] = Variable<String>(merchant.value);
    }
    if (tagSyncIdsJson.present) {
      map['tag_sync_ids_json'] = Variable<String>(tagSyncIdsJson.value);
    }
    if (rewardRuleIdsJson.present) {
      map['reward_rule_ids_json'] = Variable<String>(rewardRuleIdsJson.value);
    }
    if (frequency.present) {
      map['frequency'] = Variable<String>(frequency.value);
    }
    if (interval.present) {
      map['interval'] = Variable<int>(interval.value);
    }
    if (advancedRuleJson.present) {
      map['advanced_rule_json'] = Variable<String>(advancedRuleJson.value);
    }
    if (nextRunAt.present) {
      map['next_run_at'] = Variable<DateTime>(nextRunAt.value);
    }
    if (endAt.present) {
      map['end_at'] = Variable<DateTime>(endAt.value);
    }
    if (generatedUntilAt.present) {
      map['generated_until_at'] = Variable<DateTime>(generatedUntilAt.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RecurringTransactionsCompanion(')
          ..write('id: $id, ')
          ..write('syncId: $syncId, ')
          ..write('ledgerId: $ledgerId, ')
          ..write('type: $type, ')
          ..write('amount: $amount, ')
          ..write('categoryId: $categoryId, ')
          ..write('accountId: $accountId, ')
          ..write('fromAccountId: $fromAccountId, ')
          ..write('toAccountId: $toAccountId, ')
          ..write('note: $note, ')
          ..write('merchant: $merchant, ')
          ..write('tagSyncIdsJson: $tagSyncIdsJson, ')
          ..write('rewardRuleIdsJson: $rewardRuleIdsJson, ')
          ..write('frequency: $frequency, ')
          ..write('interval: $interval, ')
          ..write('advancedRuleJson: $advancedRuleJson, ')
          ..write('nextRunAt: $nextRunAt, ')
          ..write('endAt: $endAt, ')
          ..write('generatedUntilAt: $generatedUntilAt, ')
          ..write('enabled: $enabled, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $ConversationsTable extends Conversations
    with TableInfo<$ConversationsTable, Conversation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ConversationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _ledgerIdMeta =
      const VerificationMeta('ledgerId');
  @override
  late final GeneratedColumn<int> ledgerId = GeneratedColumn<int>(
      'ledger_id', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('AI对话'));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns =>
      [id, ledgerId, title, createdAt, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'conversations';
  @override
  VerificationContext validateIntegrity(Insertable<Conversation> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('ledger_id')) {
      context.handle(_ledgerIdMeta,
          ledgerId.isAcceptableOrUnknown(data['ledger_id']!, _ledgerIdMeta));
    }
    if (data.containsKey('title')) {
      context.handle(
          _titleMeta, title.isAcceptableOrUnknown(data['title']!, _titleMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Conversation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Conversation(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      ledgerId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}ledger_id']),
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $ConversationsTable createAlias(String alias) {
    return $ConversationsTable(attachedDatabase, alias);
  }
}

class Conversation extends DataClass implements Insertable<Conversation> {
  final int id;
  final int? ledgerId;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  const Conversation(
      {required this.id,
      this.ledgerId,
      required this.title,
      required this.createdAt,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || ledgerId != null) {
      map['ledger_id'] = Variable<int>(ledgerId);
    }
    map['title'] = Variable<String>(title);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ConversationsCompanion toCompanion(bool nullToAbsent) {
    return ConversationsCompanion(
      id: Value(id),
      ledgerId: ledgerId == null && nullToAbsent
          ? const Value.absent()
          : Value(ledgerId),
      title: Value(title),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Conversation.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Conversation(
      id: serializer.fromJson<int>(json['id']),
      ledgerId: serializer.fromJson<int?>(json['ledgerId']),
      title: serializer.fromJson<String>(json['title']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'ledgerId': serializer.toJson<int?>(ledgerId),
      'title': serializer.toJson<String>(title),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Conversation copyWith(
          {int? id,
          Value<int?> ledgerId = const Value.absent(),
          String? title,
          DateTime? createdAt,
          DateTime? updatedAt}) =>
      Conversation(
        id: id ?? this.id,
        ledgerId: ledgerId.present ? ledgerId.value : this.ledgerId,
        title: title ?? this.title,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  Conversation copyWithCompanion(ConversationsCompanion data) {
    return Conversation(
      id: data.id.present ? data.id.value : this.id,
      ledgerId: data.ledgerId.present ? data.ledgerId.value : this.ledgerId,
      title: data.title.present ? data.title.value : this.title,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Conversation(')
          ..write('id: $id, ')
          ..write('ledgerId: $ledgerId, ')
          ..write('title: $title, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, ledgerId, title, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Conversation &&
          other.id == this.id &&
          other.ledgerId == this.ledgerId &&
          other.title == this.title &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class ConversationsCompanion extends UpdateCompanion<Conversation> {
  final Value<int> id;
  final Value<int?> ledgerId;
  final Value<String> title;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  const ConversationsCompanion({
    this.id = const Value.absent(),
    this.ledgerId = const Value.absent(),
    this.title = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  ConversationsCompanion.insert({
    this.id = const Value.absent(),
    this.ledgerId = const Value.absent(),
    this.title = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  static Insertable<Conversation> custom({
    Expression<int>? id,
    Expression<int>? ledgerId,
    Expression<String>? title,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (ledgerId != null) 'ledger_id': ledgerId,
      if (title != null) 'title': title,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  ConversationsCompanion copyWith(
      {Value<int>? id,
      Value<int?>? ledgerId,
      Value<String>? title,
      Value<DateTime>? createdAt,
      Value<DateTime>? updatedAt}) {
    return ConversationsCompanion(
      id: id ?? this.id,
      ledgerId: ledgerId ?? this.ledgerId,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (ledgerId.present) {
      map['ledger_id'] = Variable<int>(ledgerId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ConversationsCompanion(')
          ..write('id: $id, ')
          ..write('ledgerId: $ledgerId, ')
          ..write('title: $title, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $MessagesTable extends Messages with TableInfo<$MessagesTable, Message> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MessagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _conversationIdMeta =
      const VerificationMeta('conversationId');
  @override
  late final GeneratedColumn<int> conversationId = GeneratedColumn<int>(
      'conversation_id', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _roleMeta = const VerificationMeta('role');
  @override
  late final GeneratedColumn<String> role = GeneratedColumn<String>(
      'role', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _contentMeta =
      const VerificationMeta('content');
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
      'content', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _messageTypeMeta =
      const VerificationMeta('messageType');
  @override
  late final GeneratedColumn<String> messageType = GeneratedColumn<String>(
      'message_type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _metadataMeta =
      const VerificationMeta('metadata');
  @override
  late final GeneratedColumn<String> metadata = GeneratedColumn<String>(
      'metadata', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _transactionIdMeta =
      const VerificationMeta('transactionId');
  @override
  late final GeneratedColumn<int> transactionId = GeneratedColumn<int>(
      'transaction_id', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        conversationId,
        role,
        content,
        messageType,
        metadata,
        transactionId,
        createdAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'messages';
  @override
  VerificationContext validateIntegrity(Insertable<Message> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('conversation_id')) {
      context.handle(
          _conversationIdMeta,
          conversationId.isAcceptableOrUnknown(
              data['conversation_id']!, _conversationIdMeta));
    } else if (isInserting) {
      context.missing(_conversationIdMeta);
    }
    if (data.containsKey('role')) {
      context.handle(
          _roleMeta, role.isAcceptableOrUnknown(data['role']!, _roleMeta));
    } else if (isInserting) {
      context.missing(_roleMeta);
    }
    if (data.containsKey('content')) {
      context.handle(_contentMeta,
          content.isAcceptableOrUnknown(data['content']!, _contentMeta));
    } else if (isInserting) {
      context.missing(_contentMeta);
    }
    if (data.containsKey('message_type')) {
      context.handle(
          _messageTypeMeta,
          messageType.isAcceptableOrUnknown(
              data['message_type']!, _messageTypeMeta));
    } else if (isInserting) {
      context.missing(_messageTypeMeta);
    }
    if (data.containsKey('metadata')) {
      context.handle(_metadataMeta,
          metadata.isAcceptableOrUnknown(data['metadata']!, _metadataMeta));
    }
    if (data.containsKey('transaction_id')) {
      context.handle(
          _transactionIdMeta,
          transactionId.isAcceptableOrUnknown(
              data['transaction_id']!, _transactionIdMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Message map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Message(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      conversationId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}conversation_id'])!,
      role: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}role'])!,
      content: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}content'])!,
      messageType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}message_type'])!,
      metadata: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}metadata']),
      transactionId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}transaction_id']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $MessagesTable createAlias(String alias) {
    return $MessagesTable(attachedDatabase, alias);
  }
}

class Message extends DataClass implements Insertable<Message> {
  final int id;
  final int conversationId;
  final String role;
  final String content;
  final String messageType;
  final String? metadata;
  final int? transactionId;
  final DateTime createdAt;
  const Message(
      {required this.id,
      required this.conversationId,
      required this.role,
      required this.content,
      required this.messageType,
      this.metadata,
      this.transactionId,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['conversation_id'] = Variable<int>(conversationId);
    map['role'] = Variable<String>(role);
    map['content'] = Variable<String>(content);
    map['message_type'] = Variable<String>(messageType);
    if (!nullToAbsent || metadata != null) {
      map['metadata'] = Variable<String>(metadata);
    }
    if (!nullToAbsent || transactionId != null) {
      map['transaction_id'] = Variable<int>(transactionId);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  MessagesCompanion toCompanion(bool nullToAbsent) {
    return MessagesCompanion(
      id: Value(id),
      conversationId: Value(conversationId),
      role: Value(role),
      content: Value(content),
      messageType: Value(messageType),
      metadata: metadata == null && nullToAbsent
          ? const Value.absent()
          : Value(metadata),
      transactionId: transactionId == null && nullToAbsent
          ? const Value.absent()
          : Value(transactionId),
      createdAt: Value(createdAt),
    );
  }

  factory Message.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Message(
      id: serializer.fromJson<int>(json['id']),
      conversationId: serializer.fromJson<int>(json['conversationId']),
      role: serializer.fromJson<String>(json['role']),
      content: serializer.fromJson<String>(json['content']),
      messageType: serializer.fromJson<String>(json['messageType']),
      metadata: serializer.fromJson<String?>(json['metadata']),
      transactionId: serializer.fromJson<int?>(json['transactionId']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'conversationId': serializer.toJson<int>(conversationId),
      'role': serializer.toJson<String>(role),
      'content': serializer.toJson<String>(content),
      'messageType': serializer.toJson<String>(messageType),
      'metadata': serializer.toJson<String?>(metadata),
      'transactionId': serializer.toJson<int?>(transactionId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  Message copyWith(
          {int? id,
          int? conversationId,
          String? role,
          String? content,
          String? messageType,
          Value<String?> metadata = const Value.absent(),
          Value<int?> transactionId = const Value.absent(),
          DateTime? createdAt}) =>
      Message(
        id: id ?? this.id,
        conversationId: conversationId ?? this.conversationId,
        role: role ?? this.role,
        content: content ?? this.content,
        messageType: messageType ?? this.messageType,
        metadata: metadata.present ? metadata.value : this.metadata,
        transactionId:
            transactionId.present ? transactionId.value : this.transactionId,
        createdAt: createdAt ?? this.createdAt,
      );
  Message copyWithCompanion(MessagesCompanion data) {
    return Message(
      id: data.id.present ? data.id.value : this.id,
      conversationId: data.conversationId.present
          ? data.conversationId.value
          : this.conversationId,
      role: data.role.present ? data.role.value : this.role,
      content: data.content.present ? data.content.value : this.content,
      messageType:
          data.messageType.present ? data.messageType.value : this.messageType,
      metadata: data.metadata.present ? data.metadata.value : this.metadata,
      transactionId: data.transactionId.present
          ? data.transactionId.value
          : this.transactionId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Message(')
          ..write('id: $id, ')
          ..write('conversationId: $conversationId, ')
          ..write('role: $role, ')
          ..write('content: $content, ')
          ..write('messageType: $messageType, ')
          ..write('metadata: $metadata, ')
          ..write('transactionId: $transactionId, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, conversationId, role, content,
      messageType, metadata, transactionId, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Message &&
          other.id == this.id &&
          other.conversationId == this.conversationId &&
          other.role == this.role &&
          other.content == this.content &&
          other.messageType == this.messageType &&
          other.metadata == this.metadata &&
          other.transactionId == this.transactionId &&
          other.createdAt == this.createdAt);
}

class MessagesCompanion extends UpdateCompanion<Message> {
  final Value<int> id;
  final Value<int> conversationId;
  final Value<String> role;
  final Value<String> content;
  final Value<String> messageType;
  final Value<String?> metadata;
  final Value<int?> transactionId;
  final Value<DateTime> createdAt;
  const MessagesCompanion({
    this.id = const Value.absent(),
    this.conversationId = const Value.absent(),
    this.role = const Value.absent(),
    this.content = const Value.absent(),
    this.messageType = const Value.absent(),
    this.metadata = const Value.absent(),
    this.transactionId = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  MessagesCompanion.insert({
    this.id = const Value.absent(),
    required int conversationId,
    required String role,
    required String content,
    required String messageType,
    this.metadata = const Value.absent(),
    this.transactionId = const Value.absent(),
    this.createdAt = const Value.absent(),
  })  : conversationId = Value(conversationId),
        role = Value(role),
        content = Value(content),
        messageType = Value(messageType);
  static Insertable<Message> custom({
    Expression<int>? id,
    Expression<int>? conversationId,
    Expression<String>? role,
    Expression<String>? content,
    Expression<String>? messageType,
    Expression<String>? metadata,
    Expression<int>? transactionId,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (conversationId != null) 'conversation_id': conversationId,
      if (role != null) 'role': role,
      if (content != null) 'content': content,
      if (messageType != null) 'message_type': messageType,
      if (metadata != null) 'metadata': metadata,
      if (transactionId != null) 'transaction_id': transactionId,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  MessagesCompanion copyWith(
      {Value<int>? id,
      Value<int>? conversationId,
      Value<String>? role,
      Value<String>? content,
      Value<String>? messageType,
      Value<String?>? metadata,
      Value<int?>? transactionId,
      Value<DateTime>? createdAt}) {
    return MessagesCompanion(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      role: role ?? this.role,
      content: content ?? this.content,
      messageType: messageType ?? this.messageType,
      metadata: metadata ?? this.metadata,
      transactionId: transactionId ?? this.transactionId,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (conversationId.present) {
      map['conversation_id'] = Variable<int>(conversationId.value);
    }
    if (role.present) {
      map['role'] = Variable<String>(role.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (messageType.present) {
      map['message_type'] = Variable<String>(messageType.value);
    }
    if (metadata.present) {
      map['metadata'] = Variable<String>(metadata.value);
    }
    if (transactionId.present) {
      map['transaction_id'] = Variable<int>(transactionId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MessagesCompanion(')
          ..write('id: $id, ')
          ..write('conversationId: $conversationId, ')
          ..write('role: $role, ')
          ..write('content: $content, ')
          ..write('messageType: $messageType, ')
          ..write('metadata: $metadata, ')
          ..write('transactionId: $transactionId, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $TagsTable extends Tags with TableInfo<$TagsTable, Tag> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TagsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _colorMeta = const VerificationMeta('color');
  @override
  late final GeneratedColumn<String> color = GeneratedColumn<String>(
      'color', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _sortOrderMeta =
      const VerificationMeta('sortOrder');
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
      'sort_order', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _syncIdMeta = const VerificationMeta('syncId');
  @override
  late final GeneratedColumn<String> syncId = GeneratedColumn<String>(
      'sync_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns =>
      [id, name, color, sortOrder, createdAt, syncId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tags';
  @override
  VerificationContext validateIntegrity(Insertable<Tag> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('color')) {
      context.handle(
          _colorMeta, color.isAcceptableOrUnknown(data['color']!, _colorMeta));
    }
    if (data.containsKey('sort_order')) {
      context.handle(_sortOrderMeta,
          sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    if (data.containsKey('sync_id')) {
      context.handle(_syncIdMeta,
          syncId.isAcceptableOrUnknown(data['sync_id']!, _syncIdMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Tag map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Tag(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      color: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}color']),
      sortOrder: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}sort_order'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      syncId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}sync_id']),
    );
  }

  @override
  $TagsTable createAlias(String alias) {
    return $TagsTable(attachedDatabase, alias);
  }
}

class Tag extends DataClass implements Insertable<Tag> {
  final int id;
  final String name;
  final String? color;
  final int sortOrder;
  final DateTime createdAt;
  final String? syncId;
  const Tag(
      {required this.id,
      required this.name,
      this.color,
      required this.sortOrder,
      required this.createdAt,
      this.syncId});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || color != null) {
      map['color'] = Variable<String>(color);
    }
    map['sort_order'] = Variable<int>(sortOrder);
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || syncId != null) {
      map['sync_id'] = Variable<String>(syncId);
    }
    return map;
  }

  TagsCompanion toCompanion(bool nullToAbsent) {
    return TagsCompanion(
      id: Value(id),
      name: Value(name),
      color:
          color == null && nullToAbsent ? const Value.absent() : Value(color),
      sortOrder: Value(sortOrder),
      createdAt: Value(createdAt),
      syncId:
          syncId == null && nullToAbsent ? const Value.absent() : Value(syncId),
    );
  }

  factory Tag.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Tag(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      color: serializer.fromJson<String?>(json['color']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      syncId: serializer.fromJson<String?>(json['syncId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'color': serializer.toJson<String?>(color),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'syncId': serializer.toJson<String?>(syncId),
    };
  }

  Tag copyWith(
          {int? id,
          String? name,
          Value<String?> color = const Value.absent(),
          int? sortOrder,
          DateTime? createdAt,
          Value<String?> syncId = const Value.absent()}) =>
      Tag(
        id: id ?? this.id,
        name: name ?? this.name,
        color: color.present ? color.value : this.color,
        sortOrder: sortOrder ?? this.sortOrder,
        createdAt: createdAt ?? this.createdAt,
        syncId: syncId.present ? syncId.value : this.syncId,
      );
  Tag copyWithCompanion(TagsCompanion data) {
    return Tag(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      color: data.color.present ? data.color.value : this.color,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      syncId: data.syncId.present ? data.syncId.value : this.syncId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Tag(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('color: $color, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('createdAt: $createdAt, ')
          ..write('syncId: $syncId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, name, color, sortOrder, createdAt, syncId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Tag &&
          other.id == this.id &&
          other.name == this.name &&
          other.color == this.color &&
          other.sortOrder == this.sortOrder &&
          other.createdAt == this.createdAt &&
          other.syncId == this.syncId);
}

class TagsCompanion extends UpdateCompanion<Tag> {
  final Value<int> id;
  final Value<String> name;
  final Value<String?> color;
  final Value<int> sortOrder;
  final Value<DateTime> createdAt;
  final Value<String?> syncId;
  const TagsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.color = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.syncId = const Value.absent(),
  });
  TagsCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    this.color = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.syncId = const Value.absent(),
  }) : name = Value(name);
  static Insertable<Tag> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? color,
    Expression<int>? sortOrder,
    Expression<DateTime>? createdAt,
    Expression<String>? syncId,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (color != null) 'color': color,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (createdAt != null) 'created_at': createdAt,
      if (syncId != null) 'sync_id': syncId,
    });
  }

  TagsCompanion copyWith(
      {Value<int>? id,
      Value<String>? name,
      Value<String?>? color,
      Value<int>? sortOrder,
      Value<DateTime>? createdAt,
      Value<String?>? syncId}) {
    return TagsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      color: color ?? this.color,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
      syncId: syncId ?? this.syncId,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (color.present) {
      map['color'] = Variable<String>(color.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (syncId.present) {
      map['sync_id'] = Variable<String>(syncId.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TagsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('color: $color, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('createdAt: $createdAt, ')
          ..write('syncId: $syncId')
          ..write(')'))
        .toString();
  }
}

class $TransactionTagsTable extends TransactionTags
    with TableInfo<$TransactionTagsTable, TransactionTag> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TransactionTagsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _transactionIdMeta =
      const VerificationMeta('transactionId');
  @override
  late final GeneratedColumn<int> transactionId = GeneratedColumn<int>(
      'transaction_id', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _tagIdMeta = const VerificationMeta('tagId');
  @override
  late final GeneratedColumn<int> tagId = GeneratedColumn<int>(
      'tag_id', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [id, transactionId, tagId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'transaction_tags';
  @override
  VerificationContext validateIntegrity(Insertable<TransactionTag> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('transaction_id')) {
      context.handle(
          _transactionIdMeta,
          transactionId.isAcceptableOrUnknown(
              data['transaction_id']!, _transactionIdMeta));
    } else if (isInserting) {
      context.missing(_transactionIdMeta);
    }
    if (data.containsKey('tag_id')) {
      context.handle(
          _tagIdMeta, tagId.isAcceptableOrUnknown(data['tag_id']!, _tagIdMeta));
    } else if (isInserting) {
      context.missing(_tagIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TransactionTag map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TransactionTag(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      transactionId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}transaction_id'])!,
      tagId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}tag_id'])!,
    );
  }

  @override
  $TransactionTagsTable createAlias(String alias) {
    return $TransactionTagsTable(attachedDatabase, alias);
  }
}

class TransactionTag extends DataClass implements Insertable<TransactionTag> {
  final int id;
  final int transactionId;
  final int tagId;
  const TransactionTag(
      {required this.id, required this.transactionId, required this.tagId});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['transaction_id'] = Variable<int>(transactionId);
    map['tag_id'] = Variable<int>(tagId);
    return map;
  }

  TransactionTagsCompanion toCompanion(bool nullToAbsent) {
    return TransactionTagsCompanion(
      id: Value(id),
      transactionId: Value(transactionId),
      tagId: Value(tagId),
    );
  }

  factory TransactionTag.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TransactionTag(
      id: serializer.fromJson<int>(json['id']),
      transactionId: serializer.fromJson<int>(json['transactionId']),
      tagId: serializer.fromJson<int>(json['tagId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'transactionId': serializer.toJson<int>(transactionId),
      'tagId': serializer.toJson<int>(tagId),
    };
  }

  TransactionTag copyWith({int? id, int? transactionId, int? tagId}) =>
      TransactionTag(
        id: id ?? this.id,
        transactionId: transactionId ?? this.transactionId,
        tagId: tagId ?? this.tagId,
      );
  TransactionTag copyWithCompanion(TransactionTagsCompanion data) {
    return TransactionTag(
      id: data.id.present ? data.id.value : this.id,
      transactionId: data.transactionId.present
          ? data.transactionId.value
          : this.transactionId,
      tagId: data.tagId.present ? data.tagId.value : this.tagId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TransactionTag(')
          ..write('id: $id, ')
          ..write('transactionId: $transactionId, ')
          ..write('tagId: $tagId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, transactionId, tagId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TransactionTag &&
          other.id == this.id &&
          other.transactionId == this.transactionId &&
          other.tagId == this.tagId);
}

class TransactionTagsCompanion extends UpdateCompanion<TransactionTag> {
  final Value<int> id;
  final Value<int> transactionId;
  final Value<int> tagId;
  const TransactionTagsCompanion({
    this.id = const Value.absent(),
    this.transactionId = const Value.absent(),
    this.tagId = const Value.absent(),
  });
  TransactionTagsCompanion.insert({
    this.id = const Value.absent(),
    required int transactionId,
    required int tagId,
  })  : transactionId = Value(transactionId),
        tagId = Value(tagId);
  static Insertable<TransactionTag> custom({
    Expression<int>? id,
    Expression<int>? transactionId,
    Expression<int>? tagId,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (transactionId != null) 'transaction_id': transactionId,
      if (tagId != null) 'tag_id': tagId,
    });
  }

  TransactionTagsCompanion copyWith(
      {Value<int>? id, Value<int>? transactionId, Value<int>? tagId}) {
    return TransactionTagsCompanion(
      id: id ?? this.id,
      transactionId: transactionId ?? this.transactionId,
      tagId: tagId ?? this.tagId,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (transactionId.present) {
      map['transaction_id'] = Variable<int>(transactionId.value);
    }
    if (tagId.present) {
      map['tag_id'] = Variable<int>(tagId.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TransactionTagsCompanion(')
          ..write('id: $id, ')
          ..write('transactionId: $transactionId, ')
          ..write('tagId: $tagId')
          ..write(')'))
        .toString();
  }
}

class $BudgetsTable extends Budgets with TableInfo<$BudgetsTable, Budget> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BudgetsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _syncIdMeta = const VerificationMeta('syncId');
  @override
  late final GeneratedColumn<String> syncId = GeneratedColumn<String>(
      'sync_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _ledgerIdMeta =
      const VerificationMeta('ledgerId');
  @override
  late final GeneratedColumn<int> ledgerId = GeneratedColumn<int>(
      'ledger_id', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
      'type', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('total'));
  static const VerificationMeta _categoryIdMeta =
      const VerificationMeta('categoryId');
  @override
  late final GeneratedColumn<int> categoryId = GeneratedColumn<int>(
      'category_id', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _amountMeta = const VerificationMeta('amount');
  @override
  late final GeneratedColumn<double> amount = GeneratedColumn<double>(
      'amount', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _periodMeta = const VerificationMeta('period');
  @override
  late final GeneratedColumn<String> period = GeneratedColumn<String>(
      'period', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('monthly'));
  static const VerificationMeta _startDayMeta =
      const VerificationMeta('startDay');
  @override
  late final GeneratedColumn<int> startDay = GeneratedColumn<int>(
      'start_day', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(1));
  static const VerificationMeta _enabledMeta =
      const VerificationMeta('enabled');
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
      'enabled', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("enabled" IN (0, 1))'),
      defaultValue: const Constant(true));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        syncId,
        ledgerId,
        type,
        categoryId,
        amount,
        period,
        startDay,
        enabled,
        createdAt,
        updatedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'budgets';
  @override
  VerificationContext validateIntegrity(Insertable<Budget> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('sync_id')) {
      context.handle(_syncIdMeta,
          syncId.isAcceptableOrUnknown(data['sync_id']!, _syncIdMeta));
    }
    if (data.containsKey('ledger_id')) {
      context.handle(_ledgerIdMeta,
          ledgerId.isAcceptableOrUnknown(data['ledger_id']!, _ledgerIdMeta));
    } else if (isInserting) {
      context.missing(_ledgerIdMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
          _typeMeta, type.isAcceptableOrUnknown(data['type']!, _typeMeta));
    }
    if (data.containsKey('category_id')) {
      context.handle(
          _categoryIdMeta,
          categoryId.isAcceptableOrUnknown(
              data['category_id']!, _categoryIdMeta));
    }
    if (data.containsKey('amount')) {
      context.handle(_amountMeta,
          amount.isAcceptableOrUnknown(data['amount']!, _amountMeta));
    } else if (isInserting) {
      context.missing(_amountMeta);
    }
    if (data.containsKey('period')) {
      context.handle(_periodMeta,
          period.isAcceptableOrUnknown(data['period']!, _periodMeta));
    }
    if (data.containsKey('start_day')) {
      context.handle(_startDayMeta,
          startDay.isAcceptableOrUnknown(data['start_day']!, _startDayMeta));
    }
    if (data.containsKey('enabled')) {
      context.handle(_enabledMeta,
          enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Budget map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Budget(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      syncId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}sync_id']),
      ledgerId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}ledger_id'])!,
      type: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}type'])!,
      categoryId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}category_id']),
      amount: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}amount'])!,
      period: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}period'])!,
      startDay: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}start_day'])!,
      enabled: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}enabled'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $BudgetsTable createAlias(String alias) {
    return $BudgetsTable(attachedDatabase, alias);
  }
}

class Budget extends DataClass implements Insertable<Budget> {
  final int id;

  /// 跨设备同步 syncId(UUID)。v22 新增,migration 给老行补 UUID;之后每次 create
  /// 都必须填。server 端按此做 entity_sync_id,跨设备 LWW 合并。
  final String? syncId;

  /// 关联账本ID
  final int ledgerId;

  /// 预算类型：total-总预算, category-分类预算
  final String type;

  /// 关联分类ID（仅分类预算有值）
  final int? categoryId;

  /// 预算金额
  final double amount;

  /// 预算周期：monthly-月度, weekly-周度, yearly-年度
  final String period;

  /// 周期起始日（1-31，月度预算；1-7，周度预算）
  final int startDay;

  /// 是否启用
  final bool enabled;

  /// 创建时间
  final DateTime createdAt;

  /// 更新时间
  final DateTime updatedAt;
  const Budget(
      {required this.id,
      this.syncId,
      required this.ledgerId,
      required this.type,
      this.categoryId,
      required this.amount,
      required this.period,
      required this.startDay,
      required this.enabled,
      required this.createdAt,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || syncId != null) {
      map['sync_id'] = Variable<String>(syncId);
    }
    map['ledger_id'] = Variable<int>(ledgerId);
    map['type'] = Variable<String>(type);
    if (!nullToAbsent || categoryId != null) {
      map['category_id'] = Variable<int>(categoryId);
    }
    map['amount'] = Variable<double>(amount);
    map['period'] = Variable<String>(period);
    map['start_day'] = Variable<int>(startDay);
    map['enabled'] = Variable<bool>(enabled);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  BudgetsCompanion toCompanion(bool nullToAbsent) {
    return BudgetsCompanion(
      id: Value(id),
      syncId:
          syncId == null && nullToAbsent ? const Value.absent() : Value(syncId),
      ledgerId: Value(ledgerId),
      type: Value(type),
      categoryId: categoryId == null && nullToAbsent
          ? const Value.absent()
          : Value(categoryId),
      amount: Value(amount),
      period: Value(period),
      startDay: Value(startDay),
      enabled: Value(enabled),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Budget.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Budget(
      id: serializer.fromJson<int>(json['id']),
      syncId: serializer.fromJson<String?>(json['syncId']),
      ledgerId: serializer.fromJson<int>(json['ledgerId']),
      type: serializer.fromJson<String>(json['type']),
      categoryId: serializer.fromJson<int?>(json['categoryId']),
      amount: serializer.fromJson<double>(json['amount']),
      period: serializer.fromJson<String>(json['period']),
      startDay: serializer.fromJson<int>(json['startDay']),
      enabled: serializer.fromJson<bool>(json['enabled']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'syncId': serializer.toJson<String?>(syncId),
      'ledgerId': serializer.toJson<int>(ledgerId),
      'type': serializer.toJson<String>(type),
      'categoryId': serializer.toJson<int?>(categoryId),
      'amount': serializer.toJson<double>(amount),
      'period': serializer.toJson<String>(period),
      'startDay': serializer.toJson<int>(startDay),
      'enabled': serializer.toJson<bool>(enabled),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Budget copyWith(
          {int? id,
          Value<String?> syncId = const Value.absent(),
          int? ledgerId,
          String? type,
          Value<int?> categoryId = const Value.absent(),
          double? amount,
          String? period,
          int? startDay,
          bool? enabled,
          DateTime? createdAt,
          DateTime? updatedAt}) =>
      Budget(
        id: id ?? this.id,
        syncId: syncId.present ? syncId.value : this.syncId,
        ledgerId: ledgerId ?? this.ledgerId,
        type: type ?? this.type,
        categoryId: categoryId.present ? categoryId.value : this.categoryId,
        amount: amount ?? this.amount,
        period: period ?? this.period,
        startDay: startDay ?? this.startDay,
        enabled: enabled ?? this.enabled,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  Budget copyWithCompanion(BudgetsCompanion data) {
    return Budget(
      id: data.id.present ? data.id.value : this.id,
      syncId: data.syncId.present ? data.syncId.value : this.syncId,
      ledgerId: data.ledgerId.present ? data.ledgerId.value : this.ledgerId,
      type: data.type.present ? data.type.value : this.type,
      categoryId:
          data.categoryId.present ? data.categoryId.value : this.categoryId,
      amount: data.amount.present ? data.amount.value : this.amount,
      period: data.period.present ? data.period.value : this.period,
      startDay: data.startDay.present ? data.startDay.value : this.startDay,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Budget(')
          ..write('id: $id, ')
          ..write('syncId: $syncId, ')
          ..write('ledgerId: $ledgerId, ')
          ..write('type: $type, ')
          ..write('categoryId: $categoryId, ')
          ..write('amount: $amount, ')
          ..write('period: $period, ')
          ..write('startDay: $startDay, ')
          ..write('enabled: $enabled, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, syncId, ledgerId, type, categoryId,
      amount, period, startDay, enabled, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Budget &&
          other.id == this.id &&
          other.syncId == this.syncId &&
          other.ledgerId == this.ledgerId &&
          other.type == this.type &&
          other.categoryId == this.categoryId &&
          other.amount == this.amount &&
          other.period == this.period &&
          other.startDay == this.startDay &&
          other.enabled == this.enabled &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class BudgetsCompanion extends UpdateCompanion<Budget> {
  final Value<int> id;
  final Value<String?> syncId;
  final Value<int> ledgerId;
  final Value<String> type;
  final Value<int?> categoryId;
  final Value<double> amount;
  final Value<String> period;
  final Value<int> startDay;
  final Value<bool> enabled;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  const BudgetsCompanion({
    this.id = const Value.absent(),
    this.syncId = const Value.absent(),
    this.ledgerId = const Value.absent(),
    this.type = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.amount = const Value.absent(),
    this.period = const Value.absent(),
    this.startDay = const Value.absent(),
    this.enabled = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  BudgetsCompanion.insert({
    this.id = const Value.absent(),
    this.syncId = const Value.absent(),
    required int ledgerId,
    this.type = const Value.absent(),
    this.categoryId = const Value.absent(),
    required double amount,
    this.period = const Value.absent(),
    this.startDay = const Value.absent(),
    this.enabled = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  })  : ledgerId = Value(ledgerId),
        amount = Value(amount);
  static Insertable<Budget> custom({
    Expression<int>? id,
    Expression<String>? syncId,
    Expression<int>? ledgerId,
    Expression<String>? type,
    Expression<int>? categoryId,
    Expression<double>? amount,
    Expression<String>? period,
    Expression<int>? startDay,
    Expression<bool>? enabled,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (syncId != null) 'sync_id': syncId,
      if (ledgerId != null) 'ledger_id': ledgerId,
      if (type != null) 'type': type,
      if (categoryId != null) 'category_id': categoryId,
      if (amount != null) 'amount': amount,
      if (period != null) 'period': period,
      if (startDay != null) 'start_day': startDay,
      if (enabled != null) 'enabled': enabled,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  BudgetsCompanion copyWith(
      {Value<int>? id,
      Value<String?>? syncId,
      Value<int>? ledgerId,
      Value<String>? type,
      Value<int?>? categoryId,
      Value<double>? amount,
      Value<String>? period,
      Value<int>? startDay,
      Value<bool>? enabled,
      Value<DateTime>? createdAt,
      Value<DateTime>? updatedAt}) {
    return BudgetsCompanion(
      id: id ?? this.id,
      syncId: syncId ?? this.syncId,
      ledgerId: ledgerId ?? this.ledgerId,
      type: type ?? this.type,
      categoryId: categoryId ?? this.categoryId,
      amount: amount ?? this.amount,
      period: period ?? this.period,
      startDay: startDay ?? this.startDay,
      enabled: enabled ?? this.enabled,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (syncId.present) {
      map['sync_id'] = Variable<String>(syncId.value);
    }
    if (ledgerId.present) {
      map['ledger_id'] = Variable<int>(ledgerId.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (categoryId.present) {
      map['category_id'] = Variable<int>(categoryId.value);
    }
    if (amount.present) {
      map['amount'] = Variable<double>(amount.value);
    }
    if (period.present) {
      map['period'] = Variable<String>(period.value);
    }
    if (startDay.present) {
      map['start_day'] = Variable<int>(startDay.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BudgetsCompanion(')
          ..write('id: $id, ')
          ..write('syncId: $syncId, ')
          ..write('ledgerId: $ledgerId, ')
          ..write('type: $type, ')
          ..write('categoryId: $categoryId, ')
          ..write('amount: $amount, ')
          ..write('period: $period, ')
          ..write('startDay: $startDay, ')
          ..write('enabled: $enabled, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $TransactionAttachmentsTable extends TransactionAttachments
    with TableInfo<$TransactionAttachmentsTable, TransactionAttachment> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TransactionAttachmentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _transactionIdMeta =
      const VerificationMeta('transactionId');
  @override
  late final GeneratedColumn<int> transactionId = GeneratedColumn<int>(
      'transaction_id', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _fileNameMeta =
      const VerificationMeta('fileName');
  @override
  late final GeneratedColumn<String> fileName = GeneratedColumn<String>(
      'file_name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _originalNameMeta =
      const VerificationMeta('originalName');
  @override
  late final GeneratedColumn<String> originalName = GeneratedColumn<String>(
      'original_name', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _fileSizeMeta =
      const VerificationMeta('fileSize');
  @override
  late final GeneratedColumn<int> fileSize = GeneratedColumn<int>(
      'file_size', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _widthMeta = const VerificationMeta('width');
  @override
  late final GeneratedColumn<int> width = GeneratedColumn<int>(
      'width', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _heightMeta = const VerificationMeta('height');
  @override
  late final GeneratedColumn<int> height = GeneratedColumn<int>(
      'height', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _sortOrderMeta =
      const VerificationMeta('sortOrder');
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
      'sort_order', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _cloudFileIdMeta =
      const VerificationMeta('cloudFileId');
  @override
  late final GeneratedColumn<String> cloudFileId = GeneratedColumn<String>(
      'cloud_file_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _cloudSha256Meta =
      const VerificationMeta('cloudSha256');
  @override
  late final GeneratedColumn<String> cloudSha256 = GeneratedColumn<String>(
      'cloud_sha256', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        transactionId,
        fileName,
        originalName,
        fileSize,
        width,
        height,
        sortOrder,
        cloudFileId,
        cloudSha256,
        createdAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'transaction_attachments';
  @override
  VerificationContext validateIntegrity(
      Insertable<TransactionAttachment> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('transaction_id')) {
      context.handle(
          _transactionIdMeta,
          transactionId.isAcceptableOrUnknown(
              data['transaction_id']!, _transactionIdMeta));
    } else if (isInserting) {
      context.missing(_transactionIdMeta);
    }
    if (data.containsKey('file_name')) {
      context.handle(_fileNameMeta,
          fileName.isAcceptableOrUnknown(data['file_name']!, _fileNameMeta));
    } else if (isInserting) {
      context.missing(_fileNameMeta);
    }
    if (data.containsKey('original_name')) {
      context.handle(
          _originalNameMeta,
          originalName.isAcceptableOrUnknown(
              data['original_name']!, _originalNameMeta));
    }
    if (data.containsKey('file_size')) {
      context.handle(_fileSizeMeta,
          fileSize.isAcceptableOrUnknown(data['file_size']!, _fileSizeMeta));
    }
    if (data.containsKey('width')) {
      context.handle(
          _widthMeta, width.isAcceptableOrUnknown(data['width']!, _widthMeta));
    }
    if (data.containsKey('height')) {
      context.handle(_heightMeta,
          height.isAcceptableOrUnknown(data['height']!, _heightMeta));
    }
    if (data.containsKey('sort_order')) {
      context.handle(_sortOrderMeta,
          sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta));
    }
    if (data.containsKey('cloud_file_id')) {
      context.handle(
          _cloudFileIdMeta,
          cloudFileId.isAcceptableOrUnknown(
              data['cloud_file_id']!, _cloudFileIdMeta));
    }
    if (data.containsKey('cloud_sha256')) {
      context.handle(
          _cloudSha256Meta,
          cloudSha256.isAcceptableOrUnknown(
              data['cloud_sha256']!, _cloudSha256Meta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TransactionAttachment map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TransactionAttachment(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      transactionId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}transaction_id'])!,
      fileName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}file_name'])!,
      originalName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}original_name']),
      fileSize: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}file_size']),
      width: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}width']),
      height: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}height']),
      sortOrder: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}sort_order'])!,
      cloudFileId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}cloud_file_id']),
      cloudSha256: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}cloud_sha256']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $TransactionAttachmentsTable createAlias(String alias) {
    return $TransactionAttachmentsTable(attachedDatabase, alias);
  }
}

class TransactionAttachment extends DataClass
    implements Insertable<TransactionAttachment> {
  final int id;
  final int transactionId;
  final String fileName;
  final String? originalName;
  final int? fileSize;
  final int? width;
  final int? height;
  final int sortOrder;
  final String? cloudFileId;
  final String? cloudSha256;
  final DateTime createdAt;
  const TransactionAttachment(
      {required this.id,
      required this.transactionId,
      required this.fileName,
      this.originalName,
      this.fileSize,
      this.width,
      this.height,
      required this.sortOrder,
      this.cloudFileId,
      this.cloudSha256,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['transaction_id'] = Variable<int>(transactionId);
    map['file_name'] = Variable<String>(fileName);
    if (!nullToAbsent || originalName != null) {
      map['original_name'] = Variable<String>(originalName);
    }
    if (!nullToAbsent || fileSize != null) {
      map['file_size'] = Variable<int>(fileSize);
    }
    if (!nullToAbsent || width != null) {
      map['width'] = Variable<int>(width);
    }
    if (!nullToAbsent || height != null) {
      map['height'] = Variable<int>(height);
    }
    map['sort_order'] = Variable<int>(sortOrder);
    if (!nullToAbsent || cloudFileId != null) {
      map['cloud_file_id'] = Variable<String>(cloudFileId);
    }
    if (!nullToAbsent || cloudSha256 != null) {
      map['cloud_sha256'] = Variable<String>(cloudSha256);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  TransactionAttachmentsCompanion toCompanion(bool nullToAbsent) {
    return TransactionAttachmentsCompanion(
      id: Value(id),
      transactionId: Value(transactionId),
      fileName: Value(fileName),
      originalName: originalName == null && nullToAbsent
          ? const Value.absent()
          : Value(originalName),
      fileSize: fileSize == null && nullToAbsent
          ? const Value.absent()
          : Value(fileSize),
      width:
          width == null && nullToAbsent ? const Value.absent() : Value(width),
      height:
          height == null && nullToAbsent ? const Value.absent() : Value(height),
      sortOrder: Value(sortOrder),
      cloudFileId: cloudFileId == null && nullToAbsent
          ? const Value.absent()
          : Value(cloudFileId),
      cloudSha256: cloudSha256 == null && nullToAbsent
          ? const Value.absent()
          : Value(cloudSha256),
      createdAt: Value(createdAt),
    );
  }

  factory TransactionAttachment.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TransactionAttachment(
      id: serializer.fromJson<int>(json['id']),
      transactionId: serializer.fromJson<int>(json['transactionId']),
      fileName: serializer.fromJson<String>(json['fileName']),
      originalName: serializer.fromJson<String?>(json['originalName']),
      fileSize: serializer.fromJson<int?>(json['fileSize']),
      width: serializer.fromJson<int?>(json['width']),
      height: serializer.fromJson<int?>(json['height']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      cloudFileId: serializer.fromJson<String?>(json['cloudFileId']),
      cloudSha256: serializer.fromJson<String?>(json['cloudSha256']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'transactionId': serializer.toJson<int>(transactionId),
      'fileName': serializer.toJson<String>(fileName),
      'originalName': serializer.toJson<String?>(originalName),
      'fileSize': serializer.toJson<int?>(fileSize),
      'width': serializer.toJson<int?>(width),
      'height': serializer.toJson<int?>(height),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'cloudFileId': serializer.toJson<String?>(cloudFileId),
      'cloudSha256': serializer.toJson<String?>(cloudSha256),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  TransactionAttachment copyWith(
          {int? id,
          int? transactionId,
          String? fileName,
          Value<String?> originalName = const Value.absent(),
          Value<int?> fileSize = const Value.absent(),
          Value<int?> width = const Value.absent(),
          Value<int?> height = const Value.absent(),
          int? sortOrder,
          Value<String?> cloudFileId = const Value.absent(),
          Value<String?> cloudSha256 = const Value.absent(),
          DateTime? createdAt}) =>
      TransactionAttachment(
        id: id ?? this.id,
        transactionId: transactionId ?? this.transactionId,
        fileName: fileName ?? this.fileName,
        originalName:
            originalName.present ? originalName.value : this.originalName,
        fileSize: fileSize.present ? fileSize.value : this.fileSize,
        width: width.present ? width.value : this.width,
        height: height.present ? height.value : this.height,
        sortOrder: sortOrder ?? this.sortOrder,
        cloudFileId: cloudFileId.present ? cloudFileId.value : this.cloudFileId,
        cloudSha256: cloudSha256.present ? cloudSha256.value : this.cloudSha256,
        createdAt: createdAt ?? this.createdAt,
      );
  TransactionAttachment copyWithCompanion(
      TransactionAttachmentsCompanion data) {
    return TransactionAttachment(
      id: data.id.present ? data.id.value : this.id,
      transactionId: data.transactionId.present
          ? data.transactionId.value
          : this.transactionId,
      fileName: data.fileName.present ? data.fileName.value : this.fileName,
      originalName: data.originalName.present
          ? data.originalName.value
          : this.originalName,
      fileSize: data.fileSize.present ? data.fileSize.value : this.fileSize,
      width: data.width.present ? data.width.value : this.width,
      height: data.height.present ? data.height.value : this.height,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      cloudFileId:
          data.cloudFileId.present ? data.cloudFileId.value : this.cloudFileId,
      cloudSha256:
          data.cloudSha256.present ? data.cloudSha256.value : this.cloudSha256,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TransactionAttachment(')
          ..write('id: $id, ')
          ..write('transactionId: $transactionId, ')
          ..write('fileName: $fileName, ')
          ..write('originalName: $originalName, ')
          ..write('fileSize: $fileSize, ')
          ..write('width: $width, ')
          ..write('height: $height, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('cloudFileId: $cloudFileId, ')
          ..write('cloudSha256: $cloudSha256, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, transactionId, fileName, originalName,
      fileSize, width, height, sortOrder, cloudFileId, cloudSha256, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TransactionAttachment &&
          other.id == this.id &&
          other.transactionId == this.transactionId &&
          other.fileName == this.fileName &&
          other.originalName == this.originalName &&
          other.fileSize == this.fileSize &&
          other.width == this.width &&
          other.height == this.height &&
          other.sortOrder == this.sortOrder &&
          other.cloudFileId == this.cloudFileId &&
          other.cloudSha256 == this.cloudSha256 &&
          other.createdAt == this.createdAt);
}

class TransactionAttachmentsCompanion
    extends UpdateCompanion<TransactionAttachment> {
  final Value<int> id;
  final Value<int> transactionId;
  final Value<String> fileName;
  final Value<String?> originalName;
  final Value<int?> fileSize;
  final Value<int?> width;
  final Value<int?> height;
  final Value<int> sortOrder;
  final Value<String?> cloudFileId;
  final Value<String?> cloudSha256;
  final Value<DateTime> createdAt;
  const TransactionAttachmentsCompanion({
    this.id = const Value.absent(),
    this.transactionId = const Value.absent(),
    this.fileName = const Value.absent(),
    this.originalName = const Value.absent(),
    this.fileSize = const Value.absent(),
    this.width = const Value.absent(),
    this.height = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.cloudFileId = const Value.absent(),
    this.cloudSha256 = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  TransactionAttachmentsCompanion.insert({
    this.id = const Value.absent(),
    required int transactionId,
    required String fileName,
    this.originalName = const Value.absent(),
    this.fileSize = const Value.absent(),
    this.width = const Value.absent(),
    this.height = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.cloudFileId = const Value.absent(),
    this.cloudSha256 = const Value.absent(),
    this.createdAt = const Value.absent(),
  })  : transactionId = Value(transactionId),
        fileName = Value(fileName);
  static Insertable<TransactionAttachment> custom({
    Expression<int>? id,
    Expression<int>? transactionId,
    Expression<String>? fileName,
    Expression<String>? originalName,
    Expression<int>? fileSize,
    Expression<int>? width,
    Expression<int>? height,
    Expression<int>? sortOrder,
    Expression<String>? cloudFileId,
    Expression<String>? cloudSha256,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (transactionId != null) 'transaction_id': transactionId,
      if (fileName != null) 'file_name': fileName,
      if (originalName != null) 'original_name': originalName,
      if (fileSize != null) 'file_size': fileSize,
      if (width != null) 'width': width,
      if (height != null) 'height': height,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (cloudFileId != null) 'cloud_file_id': cloudFileId,
      if (cloudSha256 != null) 'cloud_sha256': cloudSha256,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  TransactionAttachmentsCompanion copyWith(
      {Value<int>? id,
      Value<int>? transactionId,
      Value<String>? fileName,
      Value<String?>? originalName,
      Value<int?>? fileSize,
      Value<int?>? width,
      Value<int?>? height,
      Value<int>? sortOrder,
      Value<String?>? cloudFileId,
      Value<String?>? cloudSha256,
      Value<DateTime>? createdAt}) {
    return TransactionAttachmentsCompanion(
      id: id ?? this.id,
      transactionId: transactionId ?? this.transactionId,
      fileName: fileName ?? this.fileName,
      originalName: originalName ?? this.originalName,
      fileSize: fileSize ?? this.fileSize,
      width: width ?? this.width,
      height: height ?? this.height,
      sortOrder: sortOrder ?? this.sortOrder,
      cloudFileId: cloudFileId ?? this.cloudFileId,
      cloudSha256: cloudSha256 ?? this.cloudSha256,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (transactionId.present) {
      map['transaction_id'] = Variable<int>(transactionId.value);
    }
    if (fileName.present) {
      map['file_name'] = Variable<String>(fileName.value);
    }
    if (originalName.present) {
      map['original_name'] = Variable<String>(originalName.value);
    }
    if (fileSize.present) {
      map['file_size'] = Variable<int>(fileSize.value);
    }
    if (width.present) {
      map['width'] = Variable<int>(width.value);
    }
    if (height.present) {
      map['height'] = Variable<int>(height.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (cloudFileId.present) {
      map['cloud_file_id'] = Variable<String>(cloudFileId.value);
    }
    if (cloudSha256.present) {
      map['cloud_sha256'] = Variable<String>(cloudSha256.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TransactionAttachmentsCompanion(')
          ..write('id: $id, ')
          ..write('transactionId: $transactionId, ')
          ..write('fileName: $fileName, ')
          ..write('originalName: $originalName, ')
          ..write('fileSize: $fileSize, ')
          ..write('width: $width, ')
          ..write('height: $height, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('cloudFileId: $cloudFileId, ')
          ..write('cloudSha256: $cloudSha256, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $LocalChangesTable extends LocalChanges
    with TableInfo<$LocalChangesTable, LocalChange> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalChangesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _entityTypeMeta =
      const VerificationMeta('entityType');
  @override
  late final GeneratedColumn<String> entityType = GeneratedColumn<String>(
      'entity_type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _entityIdMeta =
      const VerificationMeta('entityId');
  @override
  late final GeneratedColumn<int> entityId = GeneratedColumn<int>(
      'entity_id', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _entitySyncIdMeta =
      const VerificationMeta('entitySyncId');
  @override
  late final GeneratedColumn<String> entitySyncId = GeneratedColumn<String>(
      'entity_sync_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _ledgerIdMeta =
      const VerificationMeta('ledgerId');
  @override
  late final GeneratedColumn<int> ledgerId = GeneratedColumn<int>(
      'ledger_id', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _actionMeta = const VerificationMeta('action');
  @override
  late final GeneratedColumn<String> action = GeneratedColumn<String>(
      'action', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _payloadJsonMeta =
      const VerificationMeta('payloadJson');
  @override
  late final GeneratedColumn<String> payloadJson = GeneratedColumn<String>(
      'payload_json', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _pushedAtMeta =
      const VerificationMeta('pushedAt');
  @override
  late final GeneratedColumn<DateTime> pushedAt = GeneratedColumn<DateTime>(
      'pushed_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        entityType,
        entityId,
        entitySyncId,
        ledgerId,
        action,
        payloadJson,
        createdAt,
        pushedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_changes';
  @override
  VerificationContext validateIntegrity(Insertable<LocalChange> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('entity_type')) {
      context.handle(
          _entityTypeMeta,
          entityType.isAcceptableOrUnknown(
              data['entity_type']!, _entityTypeMeta));
    } else if (isInserting) {
      context.missing(_entityTypeMeta);
    }
    if (data.containsKey('entity_id')) {
      context.handle(_entityIdMeta,
          entityId.isAcceptableOrUnknown(data['entity_id']!, _entityIdMeta));
    } else if (isInserting) {
      context.missing(_entityIdMeta);
    }
    if (data.containsKey('entity_sync_id')) {
      context.handle(
          _entitySyncIdMeta,
          entitySyncId.isAcceptableOrUnknown(
              data['entity_sync_id']!, _entitySyncIdMeta));
    } else if (isInserting) {
      context.missing(_entitySyncIdMeta);
    }
    if (data.containsKey('ledger_id')) {
      context.handle(_ledgerIdMeta,
          ledgerId.isAcceptableOrUnknown(data['ledger_id']!, _ledgerIdMeta));
    } else if (isInserting) {
      context.missing(_ledgerIdMeta);
    }
    if (data.containsKey('action')) {
      context.handle(_actionMeta,
          action.isAcceptableOrUnknown(data['action']!, _actionMeta));
    } else if (isInserting) {
      context.missing(_actionMeta);
    }
    if (data.containsKey('payload_json')) {
      context.handle(
          _payloadJsonMeta,
          payloadJson.isAcceptableOrUnknown(
              data['payload_json']!, _payloadJsonMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    if (data.containsKey('pushed_at')) {
      context.handle(_pushedAtMeta,
          pushedAt.isAcceptableOrUnknown(data['pushed_at']!, _pushedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalChange map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalChange(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      entityType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}entity_type'])!,
      entityId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}entity_id'])!,
      entitySyncId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}entity_sync_id'])!,
      ledgerId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}ledger_id'])!,
      action: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}action'])!,
      payloadJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}payload_json']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      pushedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}pushed_at']),
    );
  }

  @override
  $LocalChangesTable createAlias(String alias) {
    return $LocalChangesTable(attachedDatabase, alias);
  }
}

class LocalChange extends DataClass implements Insertable<LocalChange> {
  final int id;
  final String entityType;
  final int entityId;
  final String entitySyncId;
  final int ledgerId;
  final String action;
  final String? payloadJson;
  final DateTime createdAt;
  final DateTime? pushedAt;
  const LocalChange(
      {required this.id,
      required this.entityType,
      required this.entityId,
      required this.entitySyncId,
      required this.ledgerId,
      required this.action,
      this.payloadJson,
      required this.createdAt,
      this.pushedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['entity_type'] = Variable<String>(entityType);
    map['entity_id'] = Variable<int>(entityId);
    map['entity_sync_id'] = Variable<String>(entitySyncId);
    map['ledger_id'] = Variable<int>(ledgerId);
    map['action'] = Variable<String>(action);
    if (!nullToAbsent || payloadJson != null) {
      map['payload_json'] = Variable<String>(payloadJson);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || pushedAt != null) {
      map['pushed_at'] = Variable<DateTime>(pushedAt);
    }
    return map;
  }

  LocalChangesCompanion toCompanion(bool nullToAbsent) {
    return LocalChangesCompanion(
      id: Value(id),
      entityType: Value(entityType),
      entityId: Value(entityId),
      entitySyncId: Value(entitySyncId),
      ledgerId: Value(ledgerId),
      action: Value(action),
      payloadJson: payloadJson == null && nullToAbsent
          ? const Value.absent()
          : Value(payloadJson),
      createdAt: Value(createdAt),
      pushedAt: pushedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(pushedAt),
    );
  }

  factory LocalChange.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalChange(
      id: serializer.fromJson<int>(json['id']),
      entityType: serializer.fromJson<String>(json['entityType']),
      entityId: serializer.fromJson<int>(json['entityId']),
      entitySyncId: serializer.fromJson<String>(json['entitySyncId']),
      ledgerId: serializer.fromJson<int>(json['ledgerId']),
      action: serializer.fromJson<String>(json['action']),
      payloadJson: serializer.fromJson<String?>(json['payloadJson']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      pushedAt: serializer.fromJson<DateTime?>(json['pushedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'entityType': serializer.toJson<String>(entityType),
      'entityId': serializer.toJson<int>(entityId),
      'entitySyncId': serializer.toJson<String>(entitySyncId),
      'ledgerId': serializer.toJson<int>(ledgerId),
      'action': serializer.toJson<String>(action),
      'payloadJson': serializer.toJson<String?>(payloadJson),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'pushedAt': serializer.toJson<DateTime?>(pushedAt),
    };
  }

  LocalChange copyWith(
          {int? id,
          String? entityType,
          int? entityId,
          String? entitySyncId,
          int? ledgerId,
          String? action,
          Value<String?> payloadJson = const Value.absent(),
          DateTime? createdAt,
          Value<DateTime?> pushedAt = const Value.absent()}) =>
      LocalChange(
        id: id ?? this.id,
        entityType: entityType ?? this.entityType,
        entityId: entityId ?? this.entityId,
        entitySyncId: entitySyncId ?? this.entitySyncId,
        ledgerId: ledgerId ?? this.ledgerId,
        action: action ?? this.action,
        payloadJson: payloadJson.present ? payloadJson.value : this.payloadJson,
        createdAt: createdAt ?? this.createdAt,
        pushedAt: pushedAt.present ? pushedAt.value : this.pushedAt,
      );
  LocalChange copyWithCompanion(LocalChangesCompanion data) {
    return LocalChange(
      id: data.id.present ? data.id.value : this.id,
      entityType:
          data.entityType.present ? data.entityType.value : this.entityType,
      entityId: data.entityId.present ? data.entityId.value : this.entityId,
      entitySyncId: data.entitySyncId.present
          ? data.entitySyncId.value
          : this.entitySyncId,
      ledgerId: data.ledgerId.present ? data.ledgerId.value : this.ledgerId,
      action: data.action.present ? data.action.value : this.action,
      payloadJson:
          data.payloadJson.present ? data.payloadJson.value : this.payloadJson,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      pushedAt: data.pushedAt.present ? data.pushedAt.value : this.pushedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalChange(')
          ..write('id: $id, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('entitySyncId: $entitySyncId, ')
          ..write('ledgerId: $ledgerId, ')
          ..write('action: $action, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('pushedAt: $pushedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, entityType, entityId, entitySyncId,
      ledgerId, action, payloadJson, createdAt, pushedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalChange &&
          other.id == this.id &&
          other.entityType == this.entityType &&
          other.entityId == this.entityId &&
          other.entitySyncId == this.entitySyncId &&
          other.ledgerId == this.ledgerId &&
          other.action == this.action &&
          other.payloadJson == this.payloadJson &&
          other.createdAt == this.createdAt &&
          other.pushedAt == this.pushedAt);
}

class LocalChangesCompanion extends UpdateCompanion<LocalChange> {
  final Value<int> id;
  final Value<String> entityType;
  final Value<int> entityId;
  final Value<String> entitySyncId;
  final Value<int> ledgerId;
  final Value<String> action;
  final Value<String?> payloadJson;
  final Value<DateTime> createdAt;
  final Value<DateTime?> pushedAt;
  const LocalChangesCompanion({
    this.id = const Value.absent(),
    this.entityType = const Value.absent(),
    this.entityId = const Value.absent(),
    this.entitySyncId = const Value.absent(),
    this.ledgerId = const Value.absent(),
    this.action = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.pushedAt = const Value.absent(),
  });
  LocalChangesCompanion.insert({
    this.id = const Value.absent(),
    required String entityType,
    required int entityId,
    required String entitySyncId,
    required int ledgerId,
    required String action,
    this.payloadJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.pushedAt = const Value.absent(),
  })  : entityType = Value(entityType),
        entityId = Value(entityId),
        entitySyncId = Value(entitySyncId),
        ledgerId = Value(ledgerId),
        action = Value(action);
  static Insertable<LocalChange> custom({
    Expression<int>? id,
    Expression<String>? entityType,
    Expression<int>? entityId,
    Expression<String>? entitySyncId,
    Expression<int>? ledgerId,
    Expression<String>? action,
    Expression<String>? payloadJson,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? pushedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (entityType != null) 'entity_type': entityType,
      if (entityId != null) 'entity_id': entityId,
      if (entitySyncId != null) 'entity_sync_id': entitySyncId,
      if (ledgerId != null) 'ledger_id': ledgerId,
      if (action != null) 'action': action,
      if (payloadJson != null) 'payload_json': payloadJson,
      if (createdAt != null) 'created_at': createdAt,
      if (pushedAt != null) 'pushed_at': pushedAt,
    });
  }

  LocalChangesCompanion copyWith(
      {Value<int>? id,
      Value<String>? entityType,
      Value<int>? entityId,
      Value<String>? entitySyncId,
      Value<int>? ledgerId,
      Value<String>? action,
      Value<String?>? payloadJson,
      Value<DateTime>? createdAt,
      Value<DateTime?>? pushedAt}) {
    return LocalChangesCompanion(
      id: id ?? this.id,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      entitySyncId: entitySyncId ?? this.entitySyncId,
      ledgerId: ledgerId ?? this.ledgerId,
      action: action ?? this.action,
      payloadJson: payloadJson ?? this.payloadJson,
      createdAt: createdAt ?? this.createdAt,
      pushedAt: pushedAt ?? this.pushedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (entityType.present) {
      map['entity_type'] = Variable<String>(entityType.value);
    }
    if (entityId.present) {
      map['entity_id'] = Variable<int>(entityId.value);
    }
    if (entitySyncId.present) {
      map['entity_sync_id'] = Variable<String>(entitySyncId.value);
    }
    if (ledgerId.present) {
      map['ledger_id'] = Variable<int>(ledgerId.value);
    }
    if (action.present) {
      map['action'] = Variable<String>(action.value);
    }
    if (payloadJson.present) {
      map['payload_json'] = Variable<String>(payloadJson.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (pushedAt.present) {
      map['pushed_at'] = Variable<DateTime>(pushedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalChangesCompanion(')
          ..write('id: $id, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('entitySyncId: $entitySyncId, ')
          ..write('ledgerId: $ledgerId, ')
          ..write('action: $action, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('pushedAt: $pushedAt')
          ..write(')'))
        .toString();
  }
}

class $SyncStateTable extends SyncState
    with TableInfo<$SyncStateTable, SyncStateData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncStateTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _deviceIdMeta =
      const VerificationMeta('deviceId');
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
      'device_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _providerTypeMeta =
      const VerificationMeta('providerType');
  @override
  late final GeneratedColumn<String> providerType = GeneratedColumn<String>(
      'provider_type', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('beecount_cloud'));
  static const VerificationMeta _serverCursorMeta =
      const VerificationMeta('serverCursor');
  @override
  late final GeneratedColumn<int> serverCursor = GeneratedColumn<int>(
      'server_cursor', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _lastPushAtMeta =
      const VerificationMeta('lastPushAt');
  @override
  late final GeneratedColumn<DateTime> lastPushAt = GeneratedColumn<DateTime>(
      'last_push_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _lastPullAtMeta =
      const VerificationMeta('lastPullAt');
  @override
  late final GeneratedColumn<DateTime> lastPullAt = GeneratedColumn<DateTime>(
      'last_pull_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns =>
      [id, deviceId, providerType, serverCursor, lastPushAt, lastPullAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_state';
  @override
  VerificationContext validateIntegrity(Insertable<SyncStateData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('device_id')) {
      context.handle(_deviceIdMeta,
          deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta));
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('provider_type')) {
      context.handle(
          _providerTypeMeta,
          providerType.isAcceptableOrUnknown(
              data['provider_type']!, _providerTypeMeta));
    }
    if (data.containsKey('server_cursor')) {
      context.handle(
          _serverCursorMeta,
          serverCursor.isAcceptableOrUnknown(
              data['server_cursor']!, _serverCursorMeta));
    }
    if (data.containsKey('last_push_at')) {
      context.handle(
          _lastPushAtMeta,
          lastPushAt.isAcceptableOrUnknown(
              data['last_push_at']!, _lastPushAtMeta));
    }
    if (data.containsKey('last_pull_at')) {
      context.handle(
          _lastPullAtMeta,
          lastPullAt.isAcceptableOrUnknown(
              data['last_pull_at']!, _lastPullAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SyncStateData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncStateData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      deviceId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}device_id'])!,
      providerType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}provider_type'])!,
      serverCursor: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}server_cursor'])!,
      lastPushAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}last_push_at']),
      lastPullAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}last_pull_at']),
    );
  }

  @override
  $SyncStateTable createAlias(String alias) {
    return $SyncStateTable(attachedDatabase, alias);
  }
}

class SyncStateData extends DataClass implements Insertable<SyncStateData> {
  final int id;
  final String deviceId;
  final String providerType;
  final int serverCursor;
  final DateTime? lastPushAt;
  final DateTime? lastPullAt;
  const SyncStateData(
      {required this.id,
      required this.deviceId,
      required this.providerType,
      required this.serverCursor,
      this.lastPushAt,
      this.lastPullAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['device_id'] = Variable<String>(deviceId);
    map['provider_type'] = Variable<String>(providerType);
    map['server_cursor'] = Variable<int>(serverCursor);
    if (!nullToAbsent || lastPushAt != null) {
      map['last_push_at'] = Variable<DateTime>(lastPushAt);
    }
    if (!nullToAbsent || lastPullAt != null) {
      map['last_pull_at'] = Variable<DateTime>(lastPullAt);
    }
    return map;
  }

  SyncStateCompanion toCompanion(bool nullToAbsent) {
    return SyncStateCompanion(
      id: Value(id),
      deviceId: Value(deviceId),
      providerType: Value(providerType),
      serverCursor: Value(serverCursor),
      lastPushAt: lastPushAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastPushAt),
      lastPullAt: lastPullAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastPullAt),
    );
  }

  factory SyncStateData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncStateData(
      id: serializer.fromJson<int>(json['id']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      providerType: serializer.fromJson<String>(json['providerType']),
      serverCursor: serializer.fromJson<int>(json['serverCursor']),
      lastPushAt: serializer.fromJson<DateTime?>(json['lastPushAt']),
      lastPullAt: serializer.fromJson<DateTime?>(json['lastPullAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'deviceId': serializer.toJson<String>(deviceId),
      'providerType': serializer.toJson<String>(providerType),
      'serverCursor': serializer.toJson<int>(serverCursor),
      'lastPushAt': serializer.toJson<DateTime?>(lastPushAt),
      'lastPullAt': serializer.toJson<DateTime?>(lastPullAt),
    };
  }

  SyncStateData copyWith(
          {int? id,
          String? deviceId,
          String? providerType,
          int? serverCursor,
          Value<DateTime?> lastPushAt = const Value.absent(),
          Value<DateTime?> lastPullAt = const Value.absent()}) =>
      SyncStateData(
        id: id ?? this.id,
        deviceId: deviceId ?? this.deviceId,
        providerType: providerType ?? this.providerType,
        serverCursor: serverCursor ?? this.serverCursor,
        lastPushAt: lastPushAt.present ? lastPushAt.value : this.lastPushAt,
        lastPullAt: lastPullAt.present ? lastPullAt.value : this.lastPullAt,
      );
  SyncStateData copyWithCompanion(SyncStateCompanion data) {
    return SyncStateData(
      id: data.id.present ? data.id.value : this.id,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      providerType: data.providerType.present
          ? data.providerType.value
          : this.providerType,
      serverCursor: data.serverCursor.present
          ? data.serverCursor.value
          : this.serverCursor,
      lastPushAt:
          data.lastPushAt.present ? data.lastPushAt.value : this.lastPushAt,
      lastPullAt:
          data.lastPullAt.present ? data.lastPullAt.value : this.lastPullAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncStateData(')
          ..write('id: $id, ')
          ..write('deviceId: $deviceId, ')
          ..write('providerType: $providerType, ')
          ..write('serverCursor: $serverCursor, ')
          ..write('lastPushAt: $lastPushAt, ')
          ..write('lastPullAt: $lastPullAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id, deviceId, providerType, serverCursor, lastPushAt, lastPullAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncStateData &&
          other.id == this.id &&
          other.deviceId == this.deviceId &&
          other.providerType == this.providerType &&
          other.serverCursor == this.serverCursor &&
          other.lastPushAt == this.lastPushAt &&
          other.lastPullAt == this.lastPullAt);
}

class SyncStateCompanion extends UpdateCompanion<SyncStateData> {
  final Value<int> id;
  final Value<String> deviceId;
  final Value<String> providerType;
  final Value<int> serverCursor;
  final Value<DateTime?> lastPushAt;
  final Value<DateTime?> lastPullAt;
  const SyncStateCompanion({
    this.id = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.providerType = const Value.absent(),
    this.serverCursor = const Value.absent(),
    this.lastPushAt = const Value.absent(),
    this.lastPullAt = const Value.absent(),
  });
  SyncStateCompanion.insert({
    this.id = const Value.absent(),
    required String deviceId,
    this.providerType = const Value.absent(),
    this.serverCursor = const Value.absent(),
    this.lastPushAt = const Value.absent(),
    this.lastPullAt = const Value.absent(),
  }) : deviceId = Value(deviceId);
  static Insertable<SyncStateData> custom({
    Expression<int>? id,
    Expression<String>? deviceId,
    Expression<String>? providerType,
    Expression<int>? serverCursor,
    Expression<DateTime>? lastPushAt,
    Expression<DateTime>? lastPullAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (deviceId != null) 'device_id': deviceId,
      if (providerType != null) 'provider_type': providerType,
      if (serverCursor != null) 'server_cursor': serverCursor,
      if (lastPushAt != null) 'last_push_at': lastPushAt,
      if (lastPullAt != null) 'last_pull_at': lastPullAt,
    });
  }

  SyncStateCompanion copyWith(
      {Value<int>? id,
      Value<String>? deviceId,
      Value<String>? providerType,
      Value<int>? serverCursor,
      Value<DateTime?>? lastPushAt,
      Value<DateTime?>? lastPullAt}) {
    return SyncStateCompanion(
      id: id ?? this.id,
      deviceId: deviceId ?? this.deviceId,
      providerType: providerType ?? this.providerType,
      serverCursor: serverCursor ?? this.serverCursor,
      lastPushAt: lastPushAt ?? this.lastPushAt,
      lastPullAt: lastPullAt ?? this.lastPullAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (providerType.present) {
      map['provider_type'] = Variable<String>(providerType.value);
    }
    if (serverCursor.present) {
      map['server_cursor'] = Variable<int>(serverCursor.value);
    }
    if (lastPushAt.present) {
      map['last_push_at'] = Variable<DateTime>(lastPushAt.value);
    }
    if (lastPullAt.present) {
      map['last_pull_at'] = Variable<DateTime>(lastPullAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncStateCompanion(')
          ..write('id: $id, ')
          ..write('deviceId: $deviceId, ')
          ..write('providerType: $providerType, ')
          ..write('serverCursor: $serverCursor, ')
          ..write('lastPushAt: $lastPushAt, ')
          ..write('lastPullAt: $lastPullAt')
          ..write(')'))
        .toString();
  }
}

class $LedgerMembersTable extends LedgerMembers
    with TableInfo<$LedgerMembersTable, LedgerMember> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LedgerMembersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ledgerSyncIdMeta =
      const VerificationMeta('ledgerSyncId');
  @override
  late final GeneratedColumn<String> ledgerSyncId = GeneratedColumn<String>(
      'ledger_sync_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
      'user_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _emailMeta = const VerificationMeta('email');
  @override
  late final GeneratedColumn<String> email = GeneratedColumn<String>(
      'email', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _displayNameMeta =
      const VerificationMeta('displayName');
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
      'display_name', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _avatarUrlMeta =
      const VerificationMeta('avatarUrl');
  @override
  late final GeneratedColumn<String> avatarUrl = GeneratedColumn<String>(
      'avatar_url', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _roleMeta = const VerificationMeta('role');
  @override
  late final GeneratedColumn<String> role = GeneratedColumn<String>(
      'role', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _joinedAtMeta =
      const VerificationMeta('joinedAt');
  @override
  late final GeneratedColumn<DateTime> joinedAt = GeneratedColumn<DateTime>(
      'joined_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        ledgerSyncId,
        userId,
        email,
        displayName,
        avatarUrl,
        role,
        joinedAt,
        updatedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'ledger_members';
  @override
  VerificationContext validateIntegrity(Insertable<LedgerMember> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('ledger_sync_id')) {
      context.handle(
          _ledgerSyncIdMeta,
          ledgerSyncId.isAcceptableOrUnknown(
              data['ledger_sync_id']!, _ledgerSyncIdMeta));
    } else if (isInserting) {
      context.missing(_ledgerSyncIdMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(_userIdMeta,
          userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta));
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('email')) {
      context.handle(
          _emailMeta, email.isAcceptableOrUnknown(data['email']!, _emailMeta));
    }
    if (data.containsKey('display_name')) {
      context.handle(
          _displayNameMeta,
          displayName.isAcceptableOrUnknown(
              data['display_name']!, _displayNameMeta));
    }
    if (data.containsKey('avatar_url')) {
      context.handle(_avatarUrlMeta,
          avatarUrl.isAcceptableOrUnknown(data['avatar_url']!, _avatarUrlMeta));
    }
    if (data.containsKey('role')) {
      context.handle(
          _roleMeta, role.isAcceptableOrUnknown(data['role']!, _roleMeta));
    } else if (isInserting) {
      context.missing(_roleMeta);
    }
    if (data.containsKey('joined_at')) {
      context.handle(_joinedAtMeta,
          joinedAt.isAcceptableOrUnknown(data['joined_at']!, _joinedAtMeta));
    } else if (isInserting) {
      context.missing(_joinedAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {ledgerSyncId, userId};
  @override
  LedgerMember map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LedgerMember(
      ledgerSyncId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}ledger_sync_id'])!,
      userId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}user_id'])!,
      email: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}email']),
      displayName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}display_name']),
      avatarUrl: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}avatar_url']),
      role: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}role'])!,
      joinedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}joined_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $LedgerMembersTable createAlias(String alias) {
    return $LedgerMembersTable(attachedDatabase, alias);
  }
}

class LedgerMember extends DataClass implements Insertable<LedgerMember> {
  final String ledgerSyncId;
  final String userId;
  final String? email;
  final String? displayName;
  final String? avatarUrl;
  final String role;
  final DateTime joinedAt;
  final DateTime updatedAt;
  const LedgerMember(
      {required this.ledgerSyncId,
      required this.userId,
      this.email,
      this.displayName,
      this.avatarUrl,
      required this.role,
      required this.joinedAt,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['ledger_sync_id'] = Variable<String>(ledgerSyncId);
    map['user_id'] = Variable<String>(userId);
    if (!nullToAbsent || email != null) {
      map['email'] = Variable<String>(email);
    }
    if (!nullToAbsent || displayName != null) {
      map['display_name'] = Variable<String>(displayName);
    }
    if (!nullToAbsent || avatarUrl != null) {
      map['avatar_url'] = Variable<String>(avatarUrl);
    }
    map['role'] = Variable<String>(role);
    map['joined_at'] = Variable<DateTime>(joinedAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  LedgerMembersCompanion toCompanion(bool nullToAbsent) {
    return LedgerMembersCompanion(
      ledgerSyncId: Value(ledgerSyncId),
      userId: Value(userId),
      email:
          email == null && nullToAbsent ? const Value.absent() : Value(email),
      displayName: displayName == null && nullToAbsent
          ? const Value.absent()
          : Value(displayName),
      avatarUrl: avatarUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(avatarUrl),
      role: Value(role),
      joinedAt: Value(joinedAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory LedgerMember.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LedgerMember(
      ledgerSyncId: serializer.fromJson<String>(json['ledgerSyncId']),
      userId: serializer.fromJson<String>(json['userId']),
      email: serializer.fromJson<String?>(json['email']),
      displayName: serializer.fromJson<String?>(json['displayName']),
      avatarUrl: serializer.fromJson<String?>(json['avatarUrl']),
      role: serializer.fromJson<String>(json['role']),
      joinedAt: serializer.fromJson<DateTime>(json['joinedAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ledgerSyncId': serializer.toJson<String>(ledgerSyncId),
      'userId': serializer.toJson<String>(userId),
      'email': serializer.toJson<String?>(email),
      'displayName': serializer.toJson<String?>(displayName),
      'avatarUrl': serializer.toJson<String?>(avatarUrl),
      'role': serializer.toJson<String>(role),
      'joinedAt': serializer.toJson<DateTime>(joinedAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  LedgerMember copyWith(
          {String? ledgerSyncId,
          String? userId,
          Value<String?> email = const Value.absent(),
          Value<String?> displayName = const Value.absent(),
          Value<String?> avatarUrl = const Value.absent(),
          String? role,
          DateTime? joinedAt,
          DateTime? updatedAt}) =>
      LedgerMember(
        ledgerSyncId: ledgerSyncId ?? this.ledgerSyncId,
        userId: userId ?? this.userId,
        email: email.present ? email.value : this.email,
        displayName: displayName.present ? displayName.value : this.displayName,
        avatarUrl: avatarUrl.present ? avatarUrl.value : this.avatarUrl,
        role: role ?? this.role,
        joinedAt: joinedAt ?? this.joinedAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  LedgerMember copyWithCompanion(LedgerMembersCompanion data) {
    return LedgerMember(
      ledgerSyncId: data.ledgerSyncId.present
          ? data.ledgerSyncId.value
          : this.ledgerSyncId,
      userId: data.userId.present ? data.userId.value : this.userId,
      email: data.email.present ? data.email.value : this.email,
      displayName:
          data.displayName.present ? data.displayName.value : this.displayName,
      avatarUrl: data.avatarUrl.present ? data.avatarUrl.value : this.avatarUrl,
      role: data.role.present ? data.role.value : this.role,
      joinedAt: data.joinedAt.present ? data.joinedAt.value : this.joinedAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LedgerMember(')
          ..write('ledgerSyncId: $ledgerSyncId, ')
          ..write('userId: $userId, ')
          ..write('email: $email, ')
          ..write('displayName: $displayName, ')
          ..write('avatarUrl: $avatarUrl, ')
          ..write('role: $role, ')
          ..write('joinedAt: $joinedAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(ledgerSyncId, userId, email, displayName,
      avatarUrl, role, joinedAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LedgerMember &&
          other.ledgerSyncId == this.ledgerSyncId &&
          other.userId == this.userId &&
          other.email == this.email &&
          other.displayName == this.displayName &&
          other.avatarUrl == this.avatarUrl &&
          other.role == this.role &&
          other.joinedAt == this.joinedAt &&
          other.updatedAt == this.updatedAt);
}

class LedgerMembersCompanion extends UpdateCompanion<LedgerMember> {
  final Value<String> ledgerSyncId;
  final Value<String> userId;
  final Value<String?> email;
  final Value<String?> displayName;
  final Value<String?> avatarUrl;
  final Value<String> role;
  final Value<DateTime> joinedAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const LedgerMembersCompanion({
    this.ledgerSyncId = const Value.absent(),
    this.userId = const Value.absent(),
    this.email = const Value.absent(),
    this.displayName = const Value.absent(),
    this.avatarUrl = const Value.absent(),
    this.role = const Value.absent(),
    this.joinedAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LedgerMembersCompanion.insert({
    required String ledgerSyncId,
    required String userId,
    this.email = const Value.absent(),
    this.displayName = const Value.absent(),
    this.avatarUrl = const Value.absent(),
    required String role,
    required DateTime joinedAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  })  : ledgerSyncId = Value(ledgerSyncId),
        userId = Value(userId),
        role = Value(role),
        joinedAt = Value(joinedAt),
        updatedAt = Value(updatedAt);
  static Insertable<LedgerMember> custom({
    Expression<String>? ledgerSyncId,
    Expression<String>? userId,
    Expression<String>? email,
    Expression<String>? displayName,
    Expression<String>? avatarUrl,
    Expression<String>? role,
    Expression<DateTime>? joinedAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (ledgerSyncId != null) 'ledger_sync_id': ledgerSyncId,
      if (userId != null) 'user_id': userId,
      if (email != null) 'email': email,
      if (displayName != null) 'display_name': displayName,
      if (avatarUrl != null) 'avatar_url': avatarUrl,
      if (role != null) 'role': role,
      if (joinedAt != null) 'joined_at': joinedAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LedgerMembersCompanion copyWith(
      {Value<String>? ledgerSyncId,
      Value<String>? userId,
      Value<String?>? email,
      Value<String?>? displayName,
      Value<String?>? avatarUrl,
      Value<String>? role,
      Value<DateTime>? joinedAt,
      Value<DateTime>? updatedAt,
      Value<int>? rowid}) {
    return LedgerMembersCompanion(
      ledgerSyncId: ledgerSyncId ?? this.ledgerSyncId,
      userId: userId ?? this.userId,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      role: role ?? this.role,
      joinedAt: joinedAt ?? this.joinedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ledgerSyncId.present) {
      map['ledger_sync_id'] = Variable<String>(ledgerSyncId.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (email.present) {
      map['email'] = Variable<String>(email.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (avatarUrl.present) {
      map['avatar_url'] = Variable<String>(avatarUrl.value);
    }
    if (role.present) {
      map['role'] = Variable<String>(role.value);
    }
    if (joinedAt.present) {
      map['joined_at'] = Variable<DateTime>(joinedAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LedgerMembersCompanion(')
          ..write('ledgerSyncId: $ledgerSyncId, ')
          ..write('userId: $userId, ')
          ..write('email: $email, ')
          ..write('displayName: $displayName, ')
          ..write('avatarUrl: $avatarUrl, ')
          ..write('role: $role, ')
          ..write('joinedAt: $joinedAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SharedLedgerCategoriesTable extends SharedLedgerCategories
    with TableInfo<$SharedLedgerCategoriesTable, SharedLedgerCategory> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SharedLedgerCategoriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ledgerSyncIdMeta =
      const VerificationMeta('ledgerSyncId');
  @override
  late final GeneratedColumn<String> ledgerSyncId = GeneratedColumn<String>(
      'ledger_sync_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _syncIdMeta = const VerificationMeta('syncId');
  @override
  late final GeneratedColumn<String> syncId = GeneratedColumn<String>(
      'sync_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
      'kind', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _iconMeta = const VerificationMeta('icon');
  @override
  late final GeneratedColumn<String> icon = GeneratedColumn<String>(
      'icon', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _iconTypeMeta =
      const VerificationMeta('iconType');
  @override
  late final GeneratedColumn<String> iconType = GeneratedColumn<String>(
      'icon_type', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('material'));
  static const VerificationMeta _iconCloudFileIdMeta =
      const VerificationMeta('iconCloudFileId');
  @override
  late final GeneratedColumn<String> iconCloudFileId = GeneratedColumn<String>(
      'icon_cloud_file_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _iconCloudSha256Meta =
      const VerificationMeta('iconCloudSha256');
  @override
  late final GeneratedColumn<String> iconCloudSha256 = GeneratedColumn<String>(
      'icon_cloud_sha256', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _colorMeta = const VerificationMeta('color');
  @override
  late final GeneratedColumn<String> color = GeneratedColumn<String>(
      'color', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _sortOrderMeta =
      const VerificationMeta('sortOrder');
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
      'sort_order', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _levelMeta = const VerificationMeta('level');
  @override
  late final GeneratedColumn<int> level = GeneratedColumn<int>(
      'level', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(1));
  static const VerificationMeta _parentNameMeta =
      const VerificationMeta('parentName');
  @override
  late final GeneratedColumn<String> parentName = GeneratedColumn<String>(
      'parent_name', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _parentSyncIdMeta =
      const VerificationMeta('parentSyncId');
  @override
  late final GeneratedColumn<String> parentSyncId = GeneratedColumn<String>(
      'parent_sync_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        ledgerSyncId,
        syncId,
        name,
        kind,
        icon,
        iconType,
        iconCloudFileId,
        iconCloudSha256,
        color,
        sortOrder,
        level,
        parentName,
        parentSyncId,
        updatedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'shared_ledger_categories';
  @override
  VerificationContext validateIntegrity(
      Insertable<SharedLedgerCategory> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('ledger_sync_id')) {
      context.handle(
          _ledgerSyncIdMeta,
          ledgerSyncId.isAcceptableOrUnknown(
              data['ledger_sync_id']!, _ledgerSyncIdMeta));
    } else if (isInserting) {
      context.missing(_ledgerSyncIdMeta);
    }
    if (data.containsKey('sync_id')) {
      context.handle(_syncIdMeta,
          syncId.isAcceptableOrUnknown(data['sync_id']!, _syncIdMeta));
    } else if (isInserting) {
      context.missing(_syncIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
          _kindMeta, kind.isAcceptableOrUnknown(data['kind']!, _kindMeta));
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('icon')) {
      context.handle(
          _iconMeta, icon.isAcceptableOrUnknown(data['icon']!, _iconMeta));
    }
    if (data.containsKey('icon_type')) {
      context.handle(_iconTypeMeta,
          iconType.isAcceptableOrUnknown(data['icon_type']!, _iconTypeMeta));
    }
    if (data.containsKey('icon_cloud_file_id')) {
      context.handle(
          _iconCloudFileIdMeta,
          iconCloudFileId.isAcceptableOrUnknown(
              data['icon_cloud_file_id']!, _iconCloudFileIdMeta));
    }
    if (data.containsKey('icon_cloud_sha256')) {
      context.handle(
          _iconCloudSha256Meta,
          iconCloudSha256.isAcceptableOrUnknown(
              data['icon_cloud_sha256']!, _iconCloudSha256Meta));
    }
    if (data.containsKey('color')) {
      context.handle(
          _colorMeta, color.isAcceptableOrUnknown(data['color']!, _colorMeta));
    }
    if (data.containsKey('sort_order')) {
      context.handle(_sortOrderMeta,
          sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta));
    }
    if (data.containsKey('level')) {
      context.handle(
          _levelMeta, level.isAcceptableOrUnknown(data['level']!, _levelMeta));
    }
    if (data.containsKey('parent_name')) {
      context.handle(
          _parentNameMeta,
          parentName.isAcceptableOrUnknown(
              data['parent_name']!, _parentNameMeta));
    }
    if (data.containsKey('parent_sync_id')) {
      context.handle(
          _parentSyncIdMeta,
          parentSyncId.isAcceptableOrUnknown(
              data['parent_sync_id']!, _parentSyncIdMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {ledgerSyncId, syncId};
  @override
  SharedLedgerCategory map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SharedLedgerCategory(
      ledgerSyncId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}ledger_sync_id'])!,
      syncId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}sync_id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      kind: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}kind'])!,
      icon: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}icon']),
      iconType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}icon_type'])!,
      iconCloudFileId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}icon_cloud_file_id']),
      iconCloudSha256: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}icon_cloud_sha256']),
      color: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}color']),
      sortOrder: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}sort_order'])!,
      level: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}level'])!,
      parentName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}parent_name']),
      parentSyncId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}parent_sync_id']),
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $SharedLedgerCategoriesTable createAlias(String alias) {
    return $SharedLedgerCategoriesTable(attachedDatabase, alias);
  }
}

class SharedLedgerCategory extends DataClass
    implements Insertable<SharedLedgerCategory> {
  final String ledgerSyncId;
  final String syncId;
  final String name;
  final String kind;
  final String? icon;
  final String iconType;
  final String? iconCloudFileId;
  final String? iconCloudSha256;
  final String? color;
  final int sortOrder;
  final int level;
  final String? parentName;
  final String? parentSyncId;
  final DateTime updatedAt;
  const SharedLedgerCategory(
      {required this.ledgerSyncId,
      required this.syncId,
      required this.name,
      required this.kind,
      this.icon,
      required this.iconType,
      this.iconCloudFileId,
      this.iconCloudSha256,
      this.color,
      required this.sortOrder,
      required this.level,
      this.parentName,
      this.parentSyncId,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['ledger_sync_id'] = Variable<String>(ledgerSyncId);
    map['sync_id'] = Variable<String>(syncId);
    map['name'] = Variable<String>(name);
    map['kind'] = Variable<String>(kind);
    if (!nullToAbsent || icon != null) {
      map['icon'] = Variable<String>(icon);
    }
    map['icon_type'] = Variable<String>(iconType);
    if (!nullToAbsent || iconCloudFileId != null) {
      map['icon_cloud_file_id'] = Variable<String>(iconCloudFileId);
    }
    if (!nullToAbsent || iconCloudSha256 != null) {
      map['icon_cloud_sha256'] = Variable<String>(iconCloudSha256);
    }
    if (!nullToAbsent || color != null) {
      map['color'] = Variable<String>(color);
    }
    map['sort_order'] = Variable<int>(sortOrder);
    map['level'] = Variable<int>(level);
    if (!nullToAbsent || parentName != null) {
      map['parent_name'] = Variable<String>(parentName);
    }
    if (!nullToAbsent || parentSyncId != null) {
      map['parent_sync_id'] = Variable<String>(parentSyncId);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  SharedLedgerCategoriesCompanion toCompanion(bool nullToAbsent) {
    return SharedLedgerCategoriesCompanion(
      ledgerSyncId: Value(ledgerSyncId),
      syncId: Value(syncId),
      name: Value(name),
      kind: Value(kind),
      icon: icon == null && nullToAbsent ? const Value.absent() : Value(icon),
      iconType: Value(iconType),
      iconCloudFileId: iconCloudFileId == null && nullToAbsent
          ? const Value.absent()
          : Value(iconCloudFileId),
      iconCloudSha256: iconCloudSha256 == null && nullToAbsent
          ? const Value.absent()
          : Value(iconCloudSha256),
      color:
          color == null && nullToAbsent ? const Value.absent() : Value(color),
      sortOrder: Value(sortOrder),
      level: Value(level),
      parentName: parentName == null && nullToAbsent
          ? const Value.absent()
          : Value(parentName),
      parentSyncId: parentSyncId == null && nullToAbsent
          ? const Value.absent()
          : Value(parentSyncId),
      updatedAt: Value(updatedAt),
    );
  }

  factory SharedLedgerCategory.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SharedLedgerCategory(
      ledgerSyncId: serializer.fromJson<String>(json['ledgerSyncId']),
      syncId: serializer.fromJson<String>(json['syncId']),
      name: serializer.fromJson<String>(json['name']),
      kind: serializer.fromJson<String>(json['kind']),
      icon: serializer.fromJson<String?>(json['icon']),
      iconType: serializer.fromJson<String>(json['iconType']),
      iconCloudFileId: serializer.fromJson<String?>(json['iconCloudFileId']),
      iconCloudSha256: serializer.fromJson<String?>(json['iconCloudSha256']),
      color: serializer.fromJson<String?>(json['color']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      level: serializer.fromJson<int>(json['level']),
      parentName: serializer.fromJson<String?>(json['parentName']),
      parentSyncId: serializer.fromJson<String?>(json['parentSyncId']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ledgerSyncId': serializer.toJson<String>(ledgerSyncId),
      'syncId': serializer.toJson<String>(syncId),
      'name': serializer.toJson<String>(name),
      'kind': serializer.toJson<String>(kind),
      'icon': serializer.toJson<String?>(icon),
      'iconType': serializer.toJson<String>(iconType),
      'iconCloudFileId': serializer.toJson<String?>(iconCloudFileId),
      'iconCloudSha256': serializer.toJson<String?>(iconCloudSha256),
      'color': serializer.toJson<String?>(color),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'level': serializer.toJson<int>(level),
      'parentName': serializer.toJson<String?>(parentName),
      'parentSyncId': serializer.toJson<String?>(parentSyncId),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  SharedLedgerCategory copyWith(
          {String? ledgerSyncId,
          String? syncId,
          String? name,
          String? kind,
          Value<String?> icon = const Value.absent(),
          String? iconType,
          Value<String?> iconCloudFileId = const Value.absent(),
          Value<String?> iconCloudSha256 = const Value.absent(),
          Value<String?> color = const Value.absent(),
          int? sortOrder,
          int? level,
          Value<String?> parentName = const Value.absent(),
          Value<String?> parentSyncId = const Value.absent(),
          DateTime? updatedAt}) =>
      SharedLedgerCategory(
        ledgerSyncId: ledgerSyncId ?? this.ledgerSyncId,
        syncId: syncId ?? this.syncId,
        name: name ?? this.name,
        kind: kind ?? this.kind,
        icon: icon.present ? icon.value : this.icon,
        iconType: iconType ?? this.iconType,
        iconCloudFileId: iconCloudFileId.present
            ? iconCloudFileId.value
            : this.iconCloudFileId,
        iconCloudSha256: iconCloudSha256.present
            ? iconCloudSha256.value
            : this.iconCloudSha256,
        color: color.present ? color.value : this.color,
        sortOrder: sortOrder ?? this.sortOrder,
        level: level ?? this.level,
        parentName: parentName.present ? parentName.value : this.parentName,
        parentSyncId:
            parentSyncId.present ? parentSyncId.value : this.parentSyncId,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  SharedLedgerCategory copyWithCompanion(SharedLedgerCategoriesCompanion data) {
    return SharedLedgerCategory(
      ledgerSyncId: data.ledgerSyncId.present
          ? data.ledgerSyncId.value
          : this.ledgerSyncId,
      syncId: data.syncId.present ? data.syncId.value : this.syncId,
      name: data.name.present ? data.name.value : this.name,
      kind: data.kind.present ? data.kind.value : this.kind,
      icon: data.icon.present ? data.icon.value : this.icon,
      iconType: data.iconType.present ? data.iconType.value : this.iconType,
      iconCloudFileId: data.iconCloudFileId.present
          ? data.iconCloudFileId.value
          : this.iconCloudFileId,
      iconCloudSha256: data.iconCloudSha256.present
          ? data.iconCloudSha256.value
          : this.iconCloudSha256,
      color: data.color.present ? data.color.value : this.color,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      level: data.level.present ? data.level.value : this.level,
      parentName:
          data.parentName.present ? data.parentName.value : this.parentName,
      parentSyncId: data.parentSyncId.present
          ? data.parentSyncId.value
          : this.parentSyncId,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SharedLedgerCategory(')
          ..write('ledgerSyncId: $ledgerSyncId, ')
          ..write('syncId: $syncId, ')
          ..write('name: $name, ')
          ..write('kind: $kind, ')
          ..write('icon: $icon, ')
          ..write('iconType: $iconType, ')
          ..write('iconCloudFileId: $iconCloudFileId, ')
          ..write('iconCloudSha256: $iconCloudSha256, ')
          ..write('color: $color, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('level: $level, ')
          ..write('parentName: $parentName, ')
          ..write('parentSyncId: $parentSyncId, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      ledgerSyncId,
      syncId,
      name,
      kind,
      icon,
      iconType,
      iconCloudFileId,
      iconCloudSha256,
      color,
      sortOrder,
      level,
      parentName,
      parentSyncId,
      updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SharedLedgerCategory &&
          other.ledgerSyncId == this.ledgerSyncId &&
          other.syncId == this.syncId &&
          other.name == this.name &&
          other.kind == this.kind &&
          other.icon == this.icon &&
          other.iconType == this.iconType &&
          other.iconCloudFileId == this.iconCloudFileId &&
          other.iconCloudSha256 == this.iconCloudSha256 &&
          other.color == this.color &&
          other.sortOrder == this.sortOrder &&
          other.level == this.level &&
          other.parentName == this.parentName &&
          other.parentSyncId == this.parentSyncId &&
          other.updatedAt == this.updatedAt);
}

class SharedLedgerCategoriesCompanion
    extends UpdateCompanion<SharedLedgerCategory> {
  final Value<String> ledgerSyncId;
  final Value<String> syncId;
  final Value<String> name;
  final Value<String> kind;
  final Value<String?> icon;
  final Value<String> iconType;
  final Value<String?> iconCloudFileId;
  final Value<String?> iconCloudSha256;
  final Value<String?> color;
  final Value<int> sortOrder;
  final Value<int> level;
  final Value<String?> parentName;
  final Value<String?> parentSyncId;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const SharedLedgerCategoriesCompanion({
    this.ledgerSyncId = const Value.absent(),
    this.syncId = const Value.absent(),
    this.name = const Value.absent(),
    this.kind = const Value.absent(),
    this.icon = const Value.absent(),
    this.iconType = const Value.absent(),
    this.iconCloudFileId = const Value.absent(),
    this.iconCloudSha256 = const Value.absent(),
    this.color = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.level = const Value.absent(),
    this.parentName = const Value.absent(),
    this.parentSyncId = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SharedLedgerCategoriesCompanion.insert({
    required String ledgerSyncId,
    required String syncId,
    required String name,
    required String kind,
    this.icon = const Value.absent(),
    this.iconType = const Value.absent(),
    this.iconCloudFileId = const Value.absent(),
    this.iconCloudSha256 = const Value.absent(),
    this.color = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.level = const Value.absent(),
    this.parentName = const Value.absent(),
    this.parentSyncId = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  })  : ledgerSyncId = Value(ledgerSyncId),
        syncId = Value(syncId),
        name = Value(name),
        kind = Value(kind),
        updatedAt = Value(updatedAt);
  static Insertable<SharedLedgerCategory> custom({
    Expression<String>? ledgerSyncId,
    Expression<String>? syncId,
    Expression<String>? name,
    Expression<String>? kind,
    Expression<String>? icon,
    Expression<String>? iconType,
    Expression<String>? iconCloudFileId,
    Expression<String>? iconCloudSha256,
    Expression<String>? color,
    Expression<int>? sortOrder,
    Expression<int>? level,
    Expression<String>? parentName,
    Expression<String>? parentSyncId,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (ledgerSyncId != null) 'ledger_sync_id': ledgerSyncId,
      if (syncId != null) 'sync_id': syncId,
      if (name != null) 'name': name,
      if (kind != null) 'kind': kind,
      if (icon != null) 'icon': icon,
      if (iconType != null) 'icon_type': iconType,
      if (iconCloudFileId != null) 'icon_cloud_file_id': iconCloudFileId,
      if (iconCloudSha256 != null) 'icon_cloud_sha256': iconCloudSha256,
      if (color != null) 'color': color,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (level != null) 'level': level,
      if (parentName != null) 'parent_name': parentName,
      if (parentSyncId != null) 'parent_sync_id': parentSyncId,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SharedLedgerCategoriesCompanion copyWith(
      {Value<String>? ledgerSyncId,
      Value<String>? syncId,
      Value<String>? name,
      Value<String>? kind,
      Value<String?>? icon,
      Value<String>? iconType,
      Value<String?>? iconCloudFileId,
      Value<String?>? iconCloudSha256,
      Value<String?>? color,
      Value<int>? sortOrder,
      Value<int>? level,
      Value<String?>? parentName,
      Value<String?>? parentSyncId,
      Value<DateTime>? updatedAt,
      Value<int>? rowid}) {
    return SharedLedgerCategoriesCompanion(
      ledgerSyncId: ledgerSyncId ?? this.ledgerSyncId,
      syncId: syncId ?? this.syncId,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      icon: icon ?? this.icon,
      iconType: iconType ?? this.iconType,
      iconCloudFileId: iconCloudFileId ?? this.iconCloudFileId,
      iconCloudSha256: iconCloudSha256 ?? this.iconCloudSha256,
      color: color ?? this.color,
      sortOrder: sortOrder ?? this.sortOrder,
      level: level ?? this.level,
      parentName: parentName ?? this.parentName,
      parentSyncId: parentSyncId ?? this.parentSyncId,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ledgerSyncId.present) {
      map['ledger_sync_id'] = Variable<String>(ledgerSyncId.value);
    }
    if (syncId.present) {
      map['sync_id'] = Variable<String>(syncId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (icon.present) {
      map['icon'] = Variable<String>(icon.value);
    }
    if (iconType.present) {
      map['icon_type'] = Variable<String>(iconType.value);
    }
    if (iconCloudFileId.present) {
      map['icon_cloud_file_id'] = Variable<String>(iconCloudFileId.value);
    }
    if (iconCloudSha256.present) {
      map['icon_cloud_sha256'] = Variable<String>(iconCloudSha256.value);
    }
    if (color.present) {
      map['color'] = Variable<String>(color.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (level.present) {
      map['level'] = Variable<int>(level.value);
    }
    if (parentName.present) {
      map['parent_name'] = Variable<String>(parentName.value);
    }
    if (parentSyncId.present) {
      map['parent_sync_id'] = Variable<String>(parentSyncId.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SharedLedgerCategoriesCompanion(')
          ..write('ledgerSyncId: $ledgerSyncId, ')
          ..write('syncId: $syncId, ')
          ..write('name: $name, ')
          ..write('kind: $kind, ')
          ..write('icon: $icon, ')
          ..write('iconType: $iconType, ')
          ..write('iconCloudFileId: $iconCloudFileId, ')
          ..write('iconCloudSha256: $iconCloudSha256, ')
          ..write('color: $color, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('level: $level, ')
          ..write('parentName: $parentName, ')
          ..write('parentSyncId: $parentSyncId, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SharedLedgerAccountsTable extends SharedLedgerAccounts
    with TableInfo<$SharedLedgerAccountsTable, SharedLedgerAccount> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SharedLedgerAccountsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ledgerSyncIdMeta =
      const VerificationMeta('ledgerSyncId');
  @override
  late final GeneratedColumn<String> ledgerSyncId = GeneratedColumn<String>(
      'ledger_sync_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _syncIdMeta = const VerificationMeta('syncId');
  @override
  late final GeneratedColumn<String> syncId = GeneratedColumn<String>(
      'sync_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _accountTypeMeta =
      const VerificationMeta('accountType');
  @override
  late final GeneratedColumn<String> accountType = GeneratedColumn<String>(
      'account_type', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('cash'));
  static const VerificationMeta _currencyMeta =
      const VerificationMeta('currency');
  @override
  late final GeneratedColumn<String> currency = GeneratedColumn<String>(
      'currency', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('CNY'));
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
      'note', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _initialBalanceMeta =
      const VerificationMeta('initialBalance');
  @override
  late final GeneratedColumn<double> initialBalance = GeneratedColumn<double>(
      'initial_balance', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _creditLimitMeta =
      const VerificationMeta('creditLimit');
  @override
  late final GeneratedColumn<double> creditLimit = GeneratedColumn<double>(
      'credit_limit', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _billingDayMeta =
      const VerificationMeta('billingDay');
  @override
  late final GeneratedColumn<int> billingDay = GeneratedColumn<int>(
      'billing_day', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _paymentDueDayMeta =
      const VerificationMeta('paymentDueDay');
  @override
  late final GeneratedColumn<int> paymentDueDay = GeneratedColumn<int>(
      'payment_due_day', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _bankNameMeta =
      const VerificationMeta('bankName');
  @override
  late final GeneratedColumn<String> bankName = GeneratedColumn<String>(
      'bank_name', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _cardLastFourMeta =
      const VerificationMeta('cardLastFour');
  @override
  late final GeneratedColumn<String> cardLastFour = GeneratedColumn<String>(
      'card_last_four', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        ledgerSyncId,
        syncId,
        name,
        accountType,
        currency,
        note,
        initialBalance,
        creditLimit,
        billingDay,
        paymentDueDay,
        bankName,
        cardLastFour,
        updatedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'shared_ledger_accounts';
  @override
  VerificationContext validateIntegrity(
      Insertable<SharedLedgerAccount> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('ledger_sync_id')) {
      context.handle(
          _ledgerSyncIdMeta,
          ledgerSyncId.isAcceptableOrUnknown(
              data['ledger_sync_id']!, _ledgerSyncIdMeta));
    } else if (isInserting) {
      context.missing(_ledgerSyncIdMeta);
    }
    if (data.containsKey('sync_id')) {
      context.handle(_syncIdMeta,
          syncId.isAcceptableOrUnknown(data['sync_id']!, _syncIdMeta));
    } else if (isInserting) {
      context.missing(_syncIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('account_type')) {
      context.handle(
          _accountTypeMeta,
          accountType.isAcceptableOrUnknown(
              data['account_type']!, _accountTypeMeta));
    }
    if (data.containsKey('currency')) {
      context.handle(_currencyMeta,
          currency.isAcceptableOrUnknown(data['currency']!, _currencyMeta));
    }
    if (data.containsKey('note')) {
      context.handle(
          _noteMeta, note.isAcceptableOrUnknown(data['note']!, _noteMeta));
    }
    if (data.containsKey('initial_balance')) {
      context.handle(
          _initialBalanceMeta,
          initialBalance.isAcceptableOrUnknown(
              data['initial_balance']!, _initialBalanceMeta));
    }
    if (data.containsKey('credit_limit')) {
      context.handle(
          _creditLimitMeta,
          creditLimit.isAcceptableOrUnknown(
              data['credit_limit']!, _creditLimitMeta));
    }
    if (data.containsKey('billing_day')) {
      context.handle(
          _billingDayMeta,
          billingDay.isAcceptableOrUnknown(
              data['billing_day']!, _billingDayMeta));
    }
    if (data.containsKey('payment_due_day')) {
      context.handle(
          _paymentDueDayMeta,
          paymentDueDay.isAcceptableOrUnknown(
              data['payment_due_day']!, _paymentDueDayMeta));
    }
    if (data.containsKey('bank_name')) {
      context.handle(_bankNameMeta,
          bankName.isAcceptableOrUnknown(data['bank_name']!, _bankNameMeta));
    }
    if (data.containsKey('card_last_four')) {
      context.handle(
          _cardLastFourMeta,
          cardLastFour.isAcceptableOrUnknown(
              data['card_last_four']!, _cardLastFourMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {ledgerSyncId, syncId};
  @override
  SharedLedgerAccount map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SharedLedgerAccount(
      ledgerSyncId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}ledger_sync_id'])!,
      syncId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}sync_id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      accountType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}account_type'])!,
      currency: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}currency'])!,
      note: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}note']),
      initialBalance: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}initial_balance']),
      creditLimit: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}credit_limit']),
      billingDay: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}billing_day']),
      paymentDueDay: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}payment_due_day']),
      bankName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}bank_name']),
      cardLastFour: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}card_last_four']),
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $SharedLedgerAccountsTable createAlias(String alias) {
    return $SharedLedgerAccountsTable(attachedDatabase, alias);
  }
}

class SharedLedgerAccount extends DataClass
    implements Insertable<SharedLedgerAccount> {
  final String ledgerSyncId;
  final String syncId;
  final String name;
  final String accountType;
  final String currency;
  final String? note;
  final double? initialBalance;
  final double? creditLimit;
  final int? billingDay;
  final int? paymentDueDay;
  final String? bankName;
  final String? cardLastFour;
  final DateTime updatedAt;
  const SharedLedgerAccount(
      {required this.ledgerSyncId,
      required this.syncId,
      required this.name,
      required this.accountType,
      required this.currency,
      this.note,
      this.initialBalance,
      this.creditLimit,
      this.billingDay,
      this.paymentDueDay,
      this.bankName,
      this.cardLastFour,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['ledger_sync_id'] = Variable<String>(ledgerSyncId);
    map['sync_id'] = Variable<String>(syncId);
    map['name'] = Variable<String>(name);
    map['account_type'] = Variable<String>(accountType);
    map['currency'] = Variable<String>(currency);
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    if (!nullToAbsent || initialBalance != null) {
      map['initial_balance'] = Variable<double>(initialBalance);
    }
    if (!nullToAbsent || creditLimit != null) {
      map['credit_limit'] = Variable<double>(creditLimit);
    }
    if (!nullToAbsent || billingDay != null) {
      map['billing_day'] = Variable<int>(billingDay);
    }
    if (!nullToAbsent || paymentDueDay != null) {
      map['payment_due_day'] = Variable<int>(paymentDueDay);
    }
    if (!nullToAbsent || bankName != null) {
      map['bank_name'] = Variable<String>(bankName);
    }
    if (!nullToAbsent || cardLastFour != null) {
      map['card_last_four'] = Variable<String>(cardLastFour);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  SharedLedgerAccountsCompanion toCompanion(bool nullToAbsent) {
    return SharedLedgerAccountsCompanion(
      ledgerSyncId: Value(ledgerSyncId),
      syncId: Value(syncId),
      name: Value(name),
      accountType: Value(accountType),
      currency: Value(currency),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      initialBalance: initialBalance == null && nullToAbsent
          ? const Value.absent()
          : Value(initialBalance),
      creditLimit: creditLimit == null && nullToAbsent
          ? const Value.absent()
          : Value(creditLimit),
      billingDay: billingDay == null && nullToAbsent
          ? const Value.absent()
          : Value(billingDay),
      paymentDueDay: paymentDueDay == null && nullToAbsent
          ? const Value.absent()
          : Value(paymentDueDay),
      bankName: bankName == null && nullToAbsent
          ? const Value.absent()
          : Value(bankName),
      cardLastFour: cardLastFour == null && nullToAbsent
          ? const Value.absent()
          : Value(cardLastFour),
      updatedAt: Value(updatedAt),
    );
  }

  factory SharedLedgerAccount.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SharedLedgerAccount(
      ledgerSyncId: serializer.fromJson<String>(json['ledgerSyncId']),
      syncId: serializer.fromJson<String>(json['syncId']),
      name: serializer.fromJson<String>(json['name']),
      accountType: serializer.fromJson<String>(json['accountType']),
      currency: serializer.fromJson<String>(json['currency']),
      note: serializer.fromJson<String?>(json['note']),
      initialBalance: serializer.fromJson<double?>(json['initialBalance']),
      creditLimit: serializer.fromJson<double?>(json['creditLimit']),
      billingDay: serializer.fromJson<int?>(json['billingDay']),
      paymentDueDay: serializer.fromJson<int?>(json['paymentDueDay']),
      bankName: serializer.fromJson<String?>(json['bankName']),
      cardLastFour: serializer.fromJson<String?>(json['cardLastFour']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ledgerSyncId': serializer.toJson<String>(ledgerSyncId),
      'syncId': serializer.toJson<String>(syncId),
      'name': serializer.toJson<String>(name),
      'accountType': serializer.toJson<String>(accountType),
      'currency': serializer.toJson<String>(currency),
      'note': serializer.toJson<String?>(note),
      'initialBalance': serializer.toJson<double?>(initialBalance),
      'creditLimit': serializer.toJson<double?>(creditLimit),
      'billingDay': serializer.toJson<int?>(billingDay),
      'paymentDueDay': serializer.toJson<int?>(paymentDueDay),
      'bankName': serializer.toJson<String?>(bankName),
      'cardLastFour': serializer.toJson<String?>(cardLastFour),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  SharedLedgerAccount copyWith(
          {String? ledgerSyncId,
          String? syncId,
          String? name,
          String? accountType,
          String? currency,
          Value<String?> note = const Value.absent(),
          Value<double?> initialBalance = const Value.absent(),
          Value<double?> creditLimit = const Value.absent(),
          Value<int?> billingDay = const Value.absent(),
          Value<int?> paymentDueDay = const Value.absent(),
          Value<String?> bankName = const Value.absent(),
          Value<String?> cardLastFour = const Value.absent(),
          DateTime? updatedAt}) =>
      SharedLedgerAccount(
        ledgerSyncId: ledgerSyncId ?? this.ledgerSyncId,
        syncId: syncId ?? this.syncId,
        name: name ?? this.name,
        accountType: accountType ?? this.accountType,
        currency: currency ?? this.currency,
        note: note.present ? note.value : this.note,
        initialBalance:
            initialBalance.present ? initialBalance.value : this.initialBalance,
        creditLimit: creditLimit.present ? creditLimit.value : this.creditLimit,
        billingDay: billingDay.present ? billingDay.value : this.billingDay,
        paymentDueDay:
            paymentDueDay.present ? paymentDueDay.value : this.paymentDueDay,
        bankName: bankName.present ? bankName.value : this.bankName,
        cardLastFour:
            cardLastFour.present ? cardLastFour.value : this.cardLastFour,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  SharedLedgerAccount copyWithCompanion(SharedLedgerAccountsCompanion data) {
    return SharedLedgerAccount(
      ledgerSyncId: data.ledgerSyncId.present
          ? data.ledgerSyncId.value
          : this.ledgerSyncId,
      syncId: data.syncId.present ? data.syncId.value : this.syncId,
      name: data.name.present ? data.name.value : this.name,
      accountType:
          data.accountType.present ? data.accountType.value : this.accountType,
      currency: data.currency.present ? data.currency.value : this.currency,
      note: data.note.present ? data.note.value : this.note,
      initialBalance: data.initialBalance.present
          ? data.initialBalance.value
          : this.initialBalance,
      creditLimit:
          data.creditLimit.present ? data.creditLimit.value : this.creditLimit,
      billingDay:
          data.billingDay.present ? data.billingDay.value : this.billingDay,
      paymentDueDay: data.paymentDueDay.present
          ? data.paymentDueDay.value
          : this.paymentDueDay,
      bankName: data.bankName.present ? data.bankName.value : this.bankName,
      cardLastFour: data.cardLastFour.present
          ? data.cardLastFour.value
          : this.cardLastFour,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SharedLedgerAccount(')
          ..write('ledgerSyncId: $ledgerSyncId, ')
          ..write('syncId: $syncId, ')
          ..write('name: $name, ')
          ..write('accountType: $accountType, ')
          ..write('currency: $currency, ')
          ..write('note: $note, ')
          ..write('initialBalance: $initialBalance, ')
          ..write('creditLimit: $creditLimit, ')
          ..write('billingDay: $billingDay, ')
          ..write('paymentDueDay: $paymentDueDay, ')
          ..write('bankName: $bankName, ')
          ..write('cardLastFour: $cardLastFour, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      ledgerSyncId,
      syncId,
      name,
      accountType,
      currency,
      note,
      initialBalance,
      creditLimit,
      billingDay,
      paymentDueDay,
      bankName,
      cardLastFour,
      updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SharedLedgerAccount &&
          other.ledgerSyncId == this.ledgerSyncId &&
          other.syncId == this.syncId &&
          other.name == this.name &&
          other.accountType == this.accountType &&
          other.currency == this.currency &&
          other.note == this.note &&
          other.initialBalance == this.initialBalance &&
          other.creditLimit == this.creditLimit &&
          other.billingDay == this.billingDay &&
          other.paymentDueDay == this.paymentDueDay &&
          other.bankName == this.bankName &&
          other.cardLastFour == this.cardLastFour &&
          other.updatedAt == this.updatedAt);
}

class SharedLedgerAccountsCompanion
    extends UpdateCompanion<SharedLedgerAccount> {
  final Value<String> ledgerSyncId;
  final Value<String> syncId;
  final Value<String> name;
  final Value<String> accountType;
  final Value<String> currency;
  final Value<String?> note;
  final Value<double?> initialBalance;
  final Value<double?> creditLimit;
  final Value<int?> billingDay;
  final Value<int?> paymentDueDay;
  final Value<String?> bankName;
  final Value<String?> cardLastFour;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const SharedLedgerAccountsCompanion({
    this.ledgerSyncId = const Value.absent(),
    this.syncId = const Value.absent(),
    this.name = const Value.absent(),
    this.accountType = const Value.absent(),
    this.currency = const Value.absent(),
    this.note = const Value.absent(),
    this.initialBalance = const Value.absent(),
    this.creditLimit = const Value.absent(),
    this.billingDay = const Value.absent(),
    this.paymentDueDay = const Value.absent(),
    this.bankName = const Value.absent(),
    this.cardLastFour = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SharedLedgerAccountsCompanion.insert({
    required String ledgerSyncId,
    required String syncId,
    required String name,
    this.accountType = const Value.absent(),
    this.currency = const Value.absent(),
    this.note = const Value.absent(),
    this.initialBalance = const Value.absent(),
    this.creditLimit = const Value.absent(),
    this.billingDay = const Value.absent(),
    this.paymentDueDay = const Value.absent(),
    this.bankName = const Value.absent(),
    this.cardLastFour = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  })  : ledgerSyncId = Value(ledgerSyncId),
        syncId = Value(syncId),
        name = Value(name),
        updatedAt = Value(updatedAt);
  static Insertable<SharedLedgerAccount> custom({
    Expression<String>? ledgerSyncId,
    Expression<String>? syncId,
    Expression<String>? name,
    Expression<String>? accountType,
    Expression<String>? currency,
    Expression<String>? note,
    Expression<double>? initialBalance,
    Expression<double>? creditLimit,
    Expression<int>? billingDay,
    Expression<int>? paymentDueDay,
    Expression<String>? bankName,
    Expression<String>? cardLastFour,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (ledgerSyncId != null) 'ledger_sync_id': ledgerSyncId,
      if (syncId != null) 'sync_id': syncId,
      if (name != null) 'name': name,
      if (accountType != null) 'account_type': accountType,
      if (currency != null) 'currency': currency,
      if (note != null) 'note': note,
      if (initialBalance != null) 'initial_balance': initialBalance,
      if (creditLimit != null) 'credit_limit': creditLimit,
      if (billingDay != null) 'billing_day': billingDay,
      if (paymentDueDay != null) 'payment_due_day': paymentDueDay,
      if (bankName != null) 'bank_name': bankName,
      if (cardLastFour != null) 'card_last_four': cardLastFour,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SharedLedgerAccountsCompanion copyWith(
      {Value<String>? ledgerSyncId,
      Value<String>? syncId,
      Value<String>? name,
      Value<String>? accountType,
      Value<String>? currency,
      Value<String?>? note,
      Value<double?>? initialBalance,
      Value<double?>? creditLimit,
      Value<int?>? billingDay,
      Value<int?>? paymentDueDay,
      Value<String?>? bankName,
      Value<String?>? cardLastFour,
      Value<DateTime>? updatedAt,
      Value<int>? rowid}) {
    return SharedLedgerAccountsCompanion(
      ledgerSyncId: ledgerSyncId ?? this.ledgerSyncId,
      syncId: syncId ?? this.syncId,
      name: name ?? this.name,
      accountType: accountType ?? this.accountType,
      currency: currency ?? this.currency,
      note: note ?? this.note,
      initialBalance: initialBalance ?? this.initialBalance,
      creditLimit: creditLimit ?? this.creditLimit,
      billingDay: billingDay ?? this.billingDay,
      paymentDueDay: paymentDueDay ?? this.paymentDueDay,
      bankName: bankName ?? this.bankName,
      cardLastFour: cardLastFour ?? this.cardLastFour,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ledgerSyncId.present) {
      map['ledger_sync_id'] = Variable<String>(ledgerSyncId.value);
    }
    if (syncId.present) {
      map['sync_id'] = Variable<String>(syncId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (accountType.present) {
      map['account_type'] = Variable<String>(accountType.value);
    }
    if (currency.present) {
      map['currency'] = Variable<String>(currency.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (initialBalance.present) {
      map['initial_balance'] = Variable<double>(initialBalance.value);
    }
    if (creditLimit.present) {
      map['credit_limit'] = Variable<double>(creditLimit.value);
    }
    if (billingDay.present) {
      map['billing_day'] = Variable<int>(billingDay.value);
    }
    if (paymentDueDay.present) {
      map['payment_due_day'] = Variable<int>(paymentDueDay.value);
    }
    if (bankName.present) {
      map['bank_name'] = Variable<String>(bankName.value);
    }
    if (cardLastFour.present) {
      map['card_last_four'] = Variable<String>(cardLastFour.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SharedLedgerAccountsCompanion(')
          ..write('ledgerSyncId: $ledgerSyncId, ')
          ..write('syncId: $syncId, ')
          ..write('name: $name, ')
          ..write('accountType: $accountType, ')
          ..write('currency: $currency, ')
          ..write('note: $note, ')
          ..write('initialBalance: $initialBalance, ')
          ..write('creditLimit: $creditLimit, ')
          ..write('billingDay: $billingDay, ')
          ..write('paymentDueDay: $paymentDueDay, ')
          ..write('bankName: $bankName, ')
          ..write('cardLastFour: $cardLastFour, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SharedLedgerTagsTable extends SharedLedgerTags
    with TableInfo<$SharedLedgerTagsTable, SharedLedgerTag> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SharedLedgerTagsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ledgerSyncIdMeta =
      const VerificationMeta('ledgerSyncId');
  @override
  late final GeneratedColumn<String> ledgerSyncId = GeneratedColumn<String>(
      'ledger_sync_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _syncIdMeta = const VerificationMeta('syncId');
  @override
  late final GeneratedColumn<String> syncId = GeneratedColumn<String>(
      'sync_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _colorMeta = const VerificationMeta('color');
  @override
  late final GeneratedColumn<String> color = GeneratedColumn<String>(
      'color', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [ledgerSyncId, syncId, name, color, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'shared_ledger_tags';
  @override
  VerificationContext validateIntegrity(Insertable<SharedLedgerTag> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('ledger_sync_id')) {
      context.handle(
          _ledgerSyncIdMeta,
          ledgerSyncId.isAcceptableOrUnknown(
              data['ledger_sync_id']!, _ledgerSyncIdMeta));
    } else if (isInserting) {
      context.missing(_ledgerSyncIdMeta);
    }
    if (data.containsKey('sync_id')) {
      context.handle(_syncIdMeta,
          syncId.isAcceptableOrUnknown(data['sync_id']!, _syncIdMeta));
    } else if (isInserting) {
      context.missing(_syncIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('color')) {
      context.handle(
          _colorMeta, color.isAcceptableOrUnknown(data['color']!, _colorMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {ledgerSyncId, syncId};
  @override
  SharedLedgerTag map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SharedLedgerTag(
      ledgerSyncId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}ledger_sync_id'])!,
      syncId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}sync_id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      color: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}color']),
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $SharedLedgerTagsTable createAlias(String alias) {
    return $SharedLedgerTagsTable(attachedDatabase, alias);
  }
}

class SharedLedgerTag extends DataClass implements Insertable<SharedLedgerTag> {
  final String ledgerSyncId;
  final String syncId;
  final String name;
  final String? color;
  final DateTime updatedAt;
  const SharedLedgerTag(
      {required this.ledgerSyncId,
      required this.syncId,
      required this.name,
      this.color,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['ledger_sync_id'] = Variable<String>(ledgerSyncId);
    map['sync_id'] = Variable<String>(syncId);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || color != null) {
      map['color'] = Variable<String>(color);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  SharedLedgerTagsCompanion toCompanion(bool nullToAbsent) {
    return SharedLedgerTagsCompanion(
      ledgerSyncId: Value(ledgerSyncId),
      syncId: Value(syncId),
      name: Value(name),
      color:
          color == null && nullToAbsent ? const Value.absent() : Value(color),
      updatedAt: Value(updatedAt),
    );
  }

  factory SharedLedgerTag.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SharedLedgerTag(
      ledgerSyncId: serializer.fromJson<String>(json['ledgerSyncId']),
      syncId: serializer.fromJson<String>(json['syncId']),
      name: serializer.fromJson<String>(json['name']),
      color: serializer.fromJson<String?>(json['color']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ledgerSyncId': serializer.toJson<String>(ledgerSyncId),
      'syncId': serializer.toJson<String>(syncId),
      'name': serializer.toJson<String>(name),
      'color': serializer.toJson<String?>(color),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  SharedLedgerTag copyWith(
          {String? ledgerSyncId,
          String? syncId,
          String? name,
          Value<String?> color = const Value.absent(),
          DateTime? updatedAt}) =>
      SharedLedgerTag(
        ledgerSyncId: ledgerSyncId ?? this.ledgerSyncId,
        syncId: syncId ?? this.syncId,
        name: name ?? this.name,
        color: color.present ? color.value : this.color,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  SharedLedgerTag copyWithCompanion(SharedLedgerTagsCompanion data) {
    return SharedLedgerTag(
      ledgerSyncId: data.ledgerSyncId.present
          ? data.ledgerSyncId.value
          : this.ledgerSyncId,
      syncId: data.syncId.present ? data.syncId.value : this.syncId,
      name: data.name.present ? data.name.value : this.name,
      color: data.color.present ? data.color.value : this.color,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SharedLedgerTag(')
          ..write('ledgerSyncId: $ledgerSyncId, ')
          ..write('syncId: $syncId, ')
          ..write('name: $name, ')
          ..write('color: $color, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(ledgerSyncId, syncId, name, color, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SharedLedgerTag &&
          other.ledgerSyncId == this.ledgerSyncId &&
          other.syncId == this.syncId &&
          other.name == this.name &&
          other.color == this.color &&
          other.updatedAt == this.updatedAt);
}

class SharedLedgerTagsCompanion extends UpdateCompanion<SharedLedgerTag> {
  final Value<String> ledgerSyncId;
  final Value<String> syncId;
  final Value<String> name;
  final Value<String?> color;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const SharedLedgerTagsCompanion({
    this.ledgerSyncId = const Value.absent(),
    this.syncId = const Value.absent(),
    this.name = const Value.absent(),
    this.color = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SharedLedgerTagsCompanion.insert({
    required String ledgerSyncId,
    required String syncId,
    required String name,
    this.color = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  })  : ledgerSyncId = Value(ledgerSyncId),
        syncId = Value(syncId),
        name = Value(name),
        updatedAt = Value(updatedAt);
  static Insertable<SharedLedgerTag> custom({
    Expression<String>? ledgerSyncId,
    Expression<String>? syncId,
    Expression<String>? name,
    Expression<String>? color,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (ledgerSyncId != null) 'ledger_sync_id': ledgerSyncId,
      if (syncId != null) 'sync_id': syncId,
      if (name != null) 'name': name,
      if (color != null) 'color': color,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SharedLedgerTagsCompanion copyWith(
      {Value<String>? ledgerSyncId,
      Value<String>? syncId,
      Value<String>? name,
      Value<String?>? color,
      Value<DateTime>? updatedAt,
      Value<int>? rowid}) {
    return SharedLedgerTagsCompanion(
      ledgerSyncId: ledgerSyncId ?? this.ledgerSyncId,
      syncId: syncId ?? this.syncId,
      name: name ?? this.name,
      color: color ?? this.color,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ledgerSyncId.present) {
      map['ledger_sync_id'] = Variable<String>(ledgerSyncId.value);
    }
    if (syncId.present) {
      map['sync_id'] = Variable<String>(syncId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (color.present) {
      map['color'] = Variable<String>(color.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SharedLedgerTagsCompanion(')
          ..write('ledgerSyncId: $ledgerSyncId, ')
          ..write('syncId: $syncId, ')
          ..write('name: $name, ')
          ..write('color: $color, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TransactionTagOverridesTable extends TransactionTagOverrides
    with TableInfo<$TransactionTagOverridesTable, TransactionTagOverride> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TransactionTagOverridesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _transactionSyncIdMeta =
      const VerificationMeta('transactionSyncId');
  @override
  late final GeneratedColumn<String> transactionSyncId =
      GeneratedColumn<String>('transaction_sync_id', aliasedName, false,
          type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _tagSyncIdMeta =
      const VerificationMeta('tagSyncId');
  @override
  late final GeneratedColumn<String> tagSyncId = GeneratedColumn<String>(
      'tag_sync_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [transactionSyncId, tagSyncId, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'transaction_tag_overrides';
  @override
  VerificationContext validateIntegrity(
      Insertable<TransactionTagOverride> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('transaction_sync_id')) {
      context.handle(
          _transactionSyncIdMeta,
          transactionSyncId.isAcceptableOrUnknown(
              data['transaction_sync_id']!, _transactionSyncIdMeta));
    } else if (isInserting) {
      context.missing(_transactionSyncIdMeta);
    }
    if (data.containsKey('tag_sync_id')) {
      context.handle(
          _tagSyncIdMeta,
          tagSyncId.isAcceptableOrUnknown(
              data['tag_sync_id']!, _tagSyncIdMeta));
    } else if (isInserting) {
      context.missing(_tagSyncIdMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {transactionSyncId, tagSyncId};
  @override
  TransactionTagOverride map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TransactionTagOverride(
      transactionSyncId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}transaction_sync_id'])!,
      tagSyncId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}tag_sync_id'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $TransactionTagOverridesTable createAlias(String alias) {
    return $TransactionTagOverridesTable(attachedDatabase, alias);
  }
}

class TransactionTagOverride extends DataClass
    implements Insertable<TransactionTagOverride> {
  final String transactionSyncId;
  final String tagSyncId;
  final DateTime createdAt;
  const TransactionTagOverride(
      {required this.transactionSyncId,
      required this.tagSyncId,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['transaction_sync_id'] = Variable<String>(transactionSyncId);
    map['tag_sync_id'] = Variable<String>(tagSyncId);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  TransactionTagOverridesCompanion toCompanion(bool nullToAbsent) {
    return TransactionTagOverridesCompanion(
      transactionSyncId: Value(transactionSyncId),
      tagSyncId: Value(tagSyncId),
      createdAt: Value(createdAt),
    );
  }

  factory TransactionTagOverride.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TransactionTagOverride(
      transactionSyncId: serializer.fromJson<String>(json['transactionSyncId']),
      tagSyncId: serializer.fromJson<String>(json['tagSyncId']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'transactionSyncId': serializer.toJson<String>(transactionSyncId),
      'tagSyncId': serializer.toJson<String>(tagSyncId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  TransactionTagOverride copyWith(
          {String? transactionSyncId,
          String? tagSyncId,
          DateTime? createdAt}) =>
      TransactionTagOverride(
        transactionSyncId: transactionSyncId ?? this.transactionSyncId,
        tagSyncId: tagSyncId ?? this.tagSyncId,
        createdAt: createdAt ?? this.createdAt,
      );
  TransactionTagOverride copyWithCompanion(
      TransactionTagOverridesCompanion data) {
    return TransactionTagOverride(
      transactionSyncId: data.transactionSyncId.present
          ? data.transactionSyncId.value
          : this.transactionSyncId,
      tagSyncId: data.tagSyncId.present ? data.tagSyncId.value : this.tagSyncId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TransactionTagOverride(')
          ..write('transactionSyncId: $transactionSyncId, ')
          ..write('tagSyncId: $tagSyncId, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(transactionSyncId, tagSyncId, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TransactionTagOverride &&
          other.transactionSyncId == this.transactionSyncId &&
          other.tagSyncId == this.tagSyncId &&
          other.createdAt == this.createdAt);
}

class TransactionTagOverridesCompanion
    extends UpdateCompanion<TransactionTagOverride> {
  final Value<String> transactionSyncId;
  final Value<String> tagSyncId;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const TransactionTagOverridesCompanion({
    this.transactionSyncId = const Value.absent(),
    this.tagSyncId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TransactionTagOverridesCompanion.insert({
    required String transactionSyncId,
    required String tagSyncId,
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  })  : transactionSyncId = Value(transactionSyncId),
        tagSyncId = Value(tagSyncId),
        createdAt = Value(createdAt);
  static Insertable<TransactionTagOverride> custom({
    Expression<String>? transactionSyncId,
    Expression<String>? tagSyncId,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (transactionSyncId != null) 'transaction_sync_id': transactionSyncId,
      if (tagSyncId != null) 'tag_sync_id': tagSyncId,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TransactionTagOverridesCompanion copyWith(
      {Value<String>? transactionSyncId,
      Value<String>? tagSyncId,
      Value<DateTime>? createdAt,
      Value<int>? rowid}) {
    return TransactionTagOverridesCompanion(
      transactionSyncId: transactionSyncId ?? this.transactionSyncId,
      tagSyncId: tagSyncId ?? this.tagSyncId,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (transactionSyncId.present) {
      map['transaction_sync_id'] = Variable<String>(transactionSyncId.value);
    }
    if (tagSyncId.present) {
      map['tag_sync_id'] = Variable<String>(tagSyncId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TransactionTagOverridesCompanion(')
          ..write('transactionSyncId: $transactionSyncId, ')
          ..write('tagSyncId: $tagSyncId, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncPullErrorsTable extends SyncPullErrors
    with TableInfo<$SyncPullErrorsTable, SyncPullError> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncPullErrorsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _changeIdMeta =
      const VerificationMeta('changeId');
  @override
  late final GeneratedColumn<int> changeId = GeneratedColumn<int>(
      'change_id', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'));
  static const VerificationMeta _ledgerExternalIdMeta =
      const VerificationMeta('ledgerExternalId');
  @override
  late final GeneratedColumn<String> ledgerExternalId = GeneratedColumn<String>(
      'ledger_external_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _entityTypeMeta =
      const VerificationMeta('entityType');
  @override
  late final GeneratedColumn<String> entityType = GeneratedColumn<String>(
      'entity_type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _entitySyncIdMeta =
      const VerificationMeta('entitySyncId');
  @override
  late final GeneratedColumn<String> entitySyncId = GeneratedColumn<String>(
      'entity_sync_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _actionMeta = const VerificationMeta('action');
  @override
  late final GeneratedColumn<String> action = GeneratedColumn<String>(
      'action', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _rawChangeJsonMeta =
      const VerificationMeta('rawChangeJson');
  @override
  late final GeneratedColumn<String> rawChangeJson = GeneratedColumn<String>(
      'raw_change_json', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _errorClassMeta =
      const VerificationMeta('errorClass');
  @override
  late final GeneratedColumn<String> errorClass = GeneratedColumn<String>(
      'error_class', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _errorMessageMeta =
      const VerificationMeta('errorMessage');
  @override
  late final GeneratedColumn<String> errorMessage = GeneratedColumn<String>(
      'error_message', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _stackTraceMeta =
      const VerificationMeta('stackTrace');
  @override
  late final GeneratedColumn<String> stackTrace = GeneratedColumn<String>(
      'stack_trace', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _firstSeenAtMeta =
      const VerificationMeta('firstSeenAt');
  @override
  late final GeneratedColumn<DateTime> firstSeenAt = GeneratedColumn<DateTime>(
      'first_seen_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _lastAttemptAtMeta =
      const VerificationMeta('lastAttemptAt');
  @override
  late final GeneratedColumn<DateTime> lastAttemptAt =
      GeneratedColumn<DateTime>('last_attempt_at', aliasedName, false,
          type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _attemptCountMeta =
      const VerificationMeta('attemptCount');
  @override
  late final GeneratedColumn<int> attemptCount = GeneratedColumn<int>(
      'attempt_count', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(1));
  static const VerificationMeta _userActionMeta =
      const VerificationMeta('userAction');
  @override
  late final GeneratedColumn<String> userAction = GeneratedColumn<String>(
      'user_action', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _resolvedAtMeta =
      const VerificationMeta('resolvedAt');
  @override
  late final GeneratedColumn<DateTime> resolvedAt = GeneratedColumn<DateTime>(
      'resolved_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        changeId,
        ledgerExternalId,
        entityType,
        entitySyncId,
        action,
        rawChangeJson,
        errorClass,
        errorMessage,
        stackTrace,
        firstSeenAt,
        lastAttemptAt,
        attemptCount,
        userAction,
        resolvedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_pull_errors';
  @override
  VerificationContext validateIntegrity(Insertable<SyncPullError> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('change_id')) {
      context.handle(_changeIdMeta,
          changeId.isAcceptableOrUnknown(data['change_id']!, _changeIdMeta));
    } else if (isInserting) {
      context.missing(_changeIdMeta);
    }
    if (data.containsKey('ledger_external_id')) {
      context.handle(
          _ledgerExternalIdMeta,
          ledgerExternalId.isAcceptableOrUnknown(
              data['ledger_external_id']!, _ledgerExternalIdMeta));
    }
    if (data.containsKey('entity_type')) {
      context.handle(
          _entityTypeMeta,
          entityType.isAcceptableOrUnknown(
              data['entity_type']!, _entityTypeMeta));
    } else if (isInserting) {
      context.missing(_entityTypeMeta);
    }
    if (data.containsKey('entity_sync_id')) {
      context.handle(
          _entitySyncIdMeta,
          entitySyncId.isAcceptableOrUnknown(
              data['entity_sync_id']!, _entitySyncIdMeta));
    } else if (isInserting) {
      context.missing(_entitySyncIdMeta);
    }
    if (data.containsKey('action')) {
      context.handle(_actionMeta,
          action.isAcceptableOrUnknown(data['action']!, _actionMeta));
    } else if (isInserting) {
      context.missing(_actionMeta);
    }
    if (data.containsKey('raw_change_json')) {
      context.handle(
          _rawChangeJsonMeta,
          rawChangeJson.isAcceptableOrUnknown(
              data['raw_change_json']!, _rawChangeJsonMeta));
    } else if (isInserting) {
      context.missing(_rawChangeJsonMeta);
    }
    if (data.containsKey('error_class')) {
      context.handle(
          _errorClassMeta,
          errorClass.isAcceptableOrUnknown(
              data['error_class']!, _errorClassMeta));
    }
    if (data.containsKey('error_message')) {
      context.handle(
          _errorMessageMeta,
          errorMessage.isAcceptableOrUnknown(
              data['error_message']!, _errorMessageMeta));
    }
    if (data.containsKey('stack_trace')) {
      context.handle(
          _stackTraceMeta,
          stackTrace.isAcceptableOrUnknown(
              data['stack_trace']!, _stackTraceMeta));
    }
    if (data.containsKey('first_seen_at')) {
      context.handle(
          _firstSeenAtMeta,
          firstSeenAt.isAcceptableOrUnknown(
              data['first_seen_at']!, _firstSeenAtMeta));
    } else if (isInserting) {
      context.missing(_firstSeenAtMeta);
    }
    if (data.containsKey('last_attempt_at')) {
      context.handle(
          _lastAttemptAtMeta,
          lastAttemptAt.isAcceptableOrUnknown(
              data['last_attempt_at']!, _lastAttemptAtMeta));
    } else if (isInserting) {
      context.missing(_lastAttemptAtMeta);
    }
    if (data.containsKey('attempt_count')) {
      context.handle(
          _attemptCountMeta,
          attemptCount.isAcceptableOrUnknown(
              data['attempt_count']!, _attemptCountMeta));
    }
    if (data.containsKey('user_action')) {
      context.handle(
          _userActionMeta,
          userAction.isAcceptableOrUnknown(
              data['user_action']!, _userActionMeta));
    }
    if (data.containsKey('resolved_at')) {
      context.handle(
          _resolvedAtMeta,
          resolvedAt.isAcceptableOrUnknown(
              data['resolved_at']!, _resolvedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SyncPullError map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncPullError(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      changeId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}change_id'])!,
      ledgerExternalId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}ledger_external_id']),
      entityType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}entity_type'])!,
      entitySyncId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}entity_sync_id'])!,
      action: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}action'])!,
      rawChangeJson: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}raw_change_json'])!,
      errorClass: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}error_class']),
      errorMessage: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}error_message']),
      stackTrace: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}stack_trace']),
      firstSeenAt: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}first_seen_at'])!,
      lastAttemptAt: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}last_attempt_at'])!,
      attemptCount: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}attempt_count'])!,
      userAction: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}user_action']),
      resolvedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}resolved_at']),
    );
  }

  @override
  $SyncPullErrorsTable createAlias(String alias) {
    return $SyncPullErrorsTable(attachedDatabase, alias);
  }
}

class SyncPullError extends DataClass implements Insertable<SyncPullError> {
  final int id;
  final int changeId;
  final String? ledgerExternalId;
  final String entityType;
  final String entitySyncId;
  final String action;
  final String rawChangeJson;
  final String? errorClass;
  final String? errorMessage;
  final String? stackTrace;
  final DateTime firstSeenAt;
  final DateTime lastAttemptAt;
  final int attemptCount;
  final String? userAction;
  final DateTime? resolvedAt;
  const SyncPullError(
      {required this.id,
      required this.changeId,
      this.ledgerExternalId,
      required this.entityType,
      required this.entitySyncId,
      required this.action,
      required this.rawChangeJson,
      this.errorClass,
      this.errorMessage,
      this.stackTrace,
      required this.firstSeenAt,
      required this.lastAttemptAt,
      required this.attemptCount,
      this.userAction,
      this.resolvedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['change_id'] = Variable<int>(changeId);
    if (!nullToAbsent || ledgerExternalId != null) {
      map['ledger_external_id'] = Variable<String>(ledgerExternalId);
    }
    map['entity_type'] = Variable<String>(entityType);
    map['entity_sync_id'] = Variable<String>(entitySyncId);
    map['action'] = Variable<String>(action);
    map['raw_change_json'] = Variable<String>(rawChangeJson);
    if (!nullToAbsent || errorClass != null) {
      map['error_class'] = Variable<String>(errorClass);
    }
    if (!nullToAbsent || errorMessage != null) {
      map['error_message'] = Variable<String>(errorMessage);
    }
    if (!nullToAbsent || stackTrace != null) {
      map['stack_trace'] = Variable<String>(stackTrace);
    }
    map['first_seen_at'] = Variable<DateTime>(firstSeenAt);
    map['last_attempt_at'] = Variable<DateTime>(lastAttemptAt);
    map['attempt_count'] = Variable<int>(attemptCount);
    if (!nullToAbsent || userAction != null) {
      map['user_action'] = Variable<String>(userAction);
    }
    if (!nullToAbsent || resolvedAt != null) {
      map['resolved_at'] = Variable<DateTime>(resolvedAt);
    }
    return map;
  }

  SyncPullErrorsCompanion toCompanion(bool nullToAbsent) {
    return SyncPullErrorsCompanion(
      id: Value(id),
      changeId: Value(changeId),
      ledgerExternalId: ledgerExternalId == null && nullToAbsent
          ? const Value.absent()
          : Value(ledgerExternalId),
      entityType: Value(entityType),
      entitySyncId: Value(entitySyncId),
      action: Value(action),
      rawChangeJson: Value(rawChangeJson),
      errorClass: errorClass == null && nullToAbsent
          ? const Value.absent()
          : Value(errorClass),
      errorMessage: errorMessage == null && nullToAbsent
          ? const Value.absent()
          : Value(errorMessage),
      stackTrace: stackTrace == null && nullToAbsent
          ? const Value.absent()
          : Value(stackTrace),
      firstSeenAt: Value(firstSeenAt),
      lastAttemptAt: Value(lastAttemptAt),
      attemptCount: Value(attemptCount),
      userAction: userAction == null && nullToAbsent
          ? const Value.absent()
          : Value(userAction),
      resolvedAt: resolvedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(resolvedAt),
    );
  }

  factory SyncPullError.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncPullError(
      id: serializer.fromJson<int>(json['id']),
      changeId: serializer.fromJson<int>(json['changeId']),
      ledgerExternalId: serializer.fromJson<String?>(json['ledgerExternalId']),
      entityType: serializer.fromJson<String>(json['entityType']),
      entitySyncId: serializer.fromJson<String>(json['entitySyncId']),
      action: serializer.fromJson<String>(json['action']),
      rawChangeJson: serializer.fromJson<String>(json['rawChangeJson']),
      errorClass: serializer.fromJson<String?>(json['errorClass']),
      errorMessage: serializer.fromJson<String?>(json['errorMessage']),
      stackTrace: serializer.fromJson<String?>(json['stackTrace']),
      firstSeenAt: serializer.fromJson<DateTime>(json['firstSeenAt']),
      lastAttemptAt: serializer.fromJson<DateTime>(json['lastAttemptAt']),
      attemptCount: serializer.fromJson<int>(json['attemptCount']),
      userAction: serializer.fromJson<String?>(json['userAction']),
      resolvedAt: serializer.fromJson<DateTime?>(json['resolvedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'changeId': serializer.toJson<int>(changeId),
      'ledgerExternalId': serializer.toJson<String?>(ledgerExternalId),
      'entityType': serializer.toJson<String>(entityType),
      'entitySyncId': serializer.toJson<String>(entitySyncId),
      'action': serializer.toJson<String>(action),
      'rawChangeJson': serializer.toJson<String>(rawChangeJson),
      'errorClass': serializer.toJson<String?>(errorClass),
      'errorMessage': serializer.toJson<String?>(errorMessage),
      'stackTrace': serializer.toJson<String?>(stackTrace),
      'firstSeenAt': serializer.toJson<DateTime>(firstSeenAt),
      'lastAttemptAt': serializer.toJson<DateTime>(lastAttemptAt),
      'attemptCount': serializer.toJson<int>(attemptCount),
      'userAction': serializer.toJson<String?>(userAction),
      'resolvedAt': serializer.toJson<DateTime?>(resolvedAt),
    };
  }

  SyncPullError copyWith(
          {int? id,
          int? changeId,
          Value<String?> ledgerExternalId = const Value.absent(),
          String? entityType,
          String? entitySyncId,
          String? action,
          String? rawChangeJson,
          Value<String?> errorClass = const Value.absent(),
          Value<String?> errorMessage = const Value.absent(),
          Value<String?> stackTrace = const Value.absent(),
          DateTime? firstSeenAt,
          DateTime? lastAttemptAt,
          int? attemptCount,
          Value<String?> userAction = const Value.absent(),
          Value<DateTime?> resolvedAt = const Value.absent()}) =>
      SyncPullError(
        id: id ?? this.id,
        changeId: changeId ?? this.changeId,
        ledgerExternalId: ledgerExternalId.present
            ? ledgerExternalId.value
            : this.ledgerExternalId,
        entityType: entityType ?? this.entityType,
        entitySyncId: entitySyncId ?? this.entitySyncId,
        action: action ?? this.action,
        rawChangeJson: rawChangeJson ?? this.rawChangeJson,
        errorClass: errorClass.present ? errorClass.value : this.errorClass,
        errorMessage:
            errorMessage.present ? errorMessage.value : this.errorMessage,
        stackTrace: stackTrace.present ? stackTrace.value : this.stackTrace,
        firstSeenAt: firstSeenAt ?? this.firstSeenAt,
        lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
        attemptCount: attemptCount ?? this.attemptCount,
        userAction: userAction.present ? userAction.value : this.userAction,
        resolvedAt: resolvedAt.present ? resolvedAt.value : this.resolvedAt,
      );
  SyncPullError copyWithCompanion(SyncPullErrorsCompanion data) {
    return SyncPullError(
      id: data.id.present ? data.id.value : this.id,
      changeId: data.changeId.present ? data.changeId.value : this.changeId,
      ledgerExternalId: data.ledgerExternalId.present
          ? data.ledgerExternalId.value
          : this.ledgerExternalId,
      entityType:
          data.entityType.present ? data.entityType.value : this.entityType,
      entitySyncId: data.entitySyncId.present
          ? data.entitySyncId.value
          : this.entitySyncId,
      action: data.action.present ? data.action.value : this.action,
      rawChangeJson: data.rawChangeJson.present
          ? data.rawChangeJson.value
          : this.rawChangeJson,
      errorClass:
          data.errorClass.present ? data.errorClass.value : this.errorClass,
      errorMessage: data.errorMessage.present
          ? data.errorMessage.value
          : this.errorMessage,
      stackTrace:
          data.stackTrace.present ? data.stackTrace.value : this.stackTrace,
      firstSeenAt:
          data.firstSeenAt.present ? data.firstSeenAt.value : this.firstSeenAt,
      lastAttemptAt: data.lastAttemptAt.present
          ? data.lastAttemptAt.value
          : this.lastAttemptAt,
      attemptCount: data.attemptCount.present
          ? data.attemptCount.value
          : this.attemptCount,
      userAction:
          data.userAction.present ? data.userAction.value : this.userAction,
      resolvedAt:
          data.resolvedAt.present ? data.resolvedAt.value : this.resolvedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncPullError(')
          ..write('id: $id, ')
          ..write('changeId: $changeId, ')
          ..write('ledgerExternalId: $ledgerExternalId, ')
          ..write('entityType: $entityType, ')
          ..write('entitySyncId: $entitySyncId, ')
          ..write('action: $action, ')
          ..write('rawChangeJson: $rawChangeJson, ')
          ..write('errorClass: $errorClass, ')
          ..write('errorMessage: $errorMessage, ')
          ..write('stackTrace: $stackTrace, ')
          ..write('firstSeenAt: $firstSeenAt, ')
          ..write('lastAttemptAt: $lastAttemptAt, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('userAction: $userAction, ')
          ..write('resolvedAt: $resolvedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      changeId,
      ledgerExternalId,
      entityType,
      entitySyncId,
      action,
      rawChangeJson,
      errorClass,
      errorMessage,
      stackTrace,
      firstSeenAt,
      lastAttemptAt,
      attemptCount,
      userAction,
      resolvedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncPullError &&
          other.id == this.id &&
          other.changeId == this.changeId &&
          other.ledgerExternalId == this.ledgerExternalId &&
          other.entityType == this.entityType &&
          other.entitySyncId == this.entitySyncId &&
          other.action == this.action &&
          other.rawChangeJson == this.rawChangeJson &&
          other.errorClass == this.errorClass &&
          other.errorMessage == this.errorMessage &&
          other.stackTrace == this.stackTrace &&
          other.firstSeenAt == this.firstSeenAt &&
          other.lastAttemptAt == this.lastAttemptAt &&
          other.attemptCount == this.attemptCount &&
          other.userAction == this.userAction &&
          other.resolvedAt == this.resolvedAt);
}

class SyncPullErrorsCompanion extends UpdateCompanion<SyncPullError> {
  final Value<int> id;
  final Value<int> changeId;
  final Value<String?> ledgerExternalId;
  final Value<String> entityType;
  final Value<String> entitySyncId;
  final Value<String> action;
  final Value<String> rawChangeJson;
  final Value<String?> errorClass;
  final Value<String?> errorMessage;
  final Value<String?> stackTrace;
  final Value<DateTime> firstSeenAt;
  final Value<DateTime> lastAttemptAt;
  final Value<int> attemptCount;
  final Value<String?> userAction;
  final Value<DateTime?> resolvedAt;
  const SyncPullErrorsCompanion({
    this.id = const Value.absent(),
    this.changeId = const Value.absent(),
    this.ledgerExternalId = const Value.absent(),
    this.entityType = const Value.absent(),
    this.entitySyncId = const Value.absent(),
    this.action = const Value.absent(),
    this.rawChangeJson = const Value.absent(),
    this.errorClass = const Value.absent(),
    this.errorMessage = const Value.absent(),
    this.stackTrace = const Value.absent(),
    this.firstSeenAt = const Value.absent(),
    this.lastAttemptAt = const Value.absent(),
    this.attemptCount = const Value.absent(),
    this.userAction = const Value.absent(),
    this.resolvedAt = const Value.absent(),
  });
  SyncPullErrorsCompanion.insert({
    this.id = const Value.absent(),
    required int changeId,
    this.ledgerExternalId = const Value.absent(),
    required String entityType,
    required String entitySyncId,
    required String action,
    required String rawChangeJson,
    this.errorClass = const Value.absent(),
    this.errorMessage = const Value.absent(),
    this.stackTrace = const Value.absent(),
    required DateTime firstSeenAt,
    required DateTime lastAttemptAt,
    this.attemptCount = const Value.absent(),
    this.userAction = const Value.absent(),
    this.resolvedAt = const Value.absent(),
  })  : changeId = Value(changeId),
        entityType = Value(entityType),
        entitySyncId = Value(entitySyncId),
        action = Value(action),
        rawChangeJson = Value(rawChangeJson),
        firstSeenAt = Value(firstSeenAt),
        lastAttemptAt = Value(lastAttemptAt);
  static Insertable<SyncPullError> custom({
    Expression<int>? id,
    Expression<int>? changeId,
    Expression<String>? ledgerExternalId,
    Expression<String>? entityType,
    Expression<String>? entitySyncId,
    Expression<String>? action,
    Expression<String>? rawChangeJson,
    Expression<String>? errorClass,
    Expression<String>? errorMessage,
    Expression<String>? stackTrace,
    Expression<DateTime>? firstSeenAt,
    Expression<DateTime>? lastAttemptAt,
    Expression<int>? attemptCount,
    Expression<String>? userAction,
    Expression<DateTime>? resolvedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (changeId != null) 'change_id': changeId,
      if (ledgerExternalId != null) 'ledger_external_id': ledgerExternalId,
      if (entityType != null) 'entity_type': entityType,
      if (entitySyncId != null) 'entity_sync_id': entitySyncId,
      if (action != null) 'action': action,
      if (rawChangeJson != null) 'raw_change_json': rawChangeJson,
      if (errorClass != null) 'error_class': errorClass,
      if (errorMessage != null) 'error_message': errorMessage,
      if (stackTrace != null) 'stack_trace': stackTrace,
      if (firstSeenAt != null) 'first_seen_at': firstSeenAt,
      if (lastAttemptAt != null) 'last_attempt_at': lastAttemptAt,
      if (attemptCount != null) 'attempt_count': attemptCount,
      if (userAction != null) 'user_action': userAction,
      if (resolvedAt != null) 'resolved_at': resolvedAt,
    });
  }

  SyncPullErrorsCompanion copyWith(
      {Value<int>? id,
      Value<int>? changeId,
      Value<String?>? ledgerExternalId,
      Value<String>? entityType,
      Value<String>? entitySyncId,
      Value<String>? action,
      Value<String>? rawChangeJson,
      Value<String?>? errorClass,
      Value<String?>? errorMessage,
      Value<String?>? stackTrace,
      Value<DateTime>? firstSeenAt,
      Value<DateTime>? lastAttemptAt,
      Value<int>? attemptCount,
      Value<String?>? userAction,
      Value<DateTime?>? resolvedAt}) {
    return SyncPullErrorsCompanion(
      id: id ?? this.id,
      changeId: changeId ?? this.changeId,
      ledgerExternalId: ledgerExternalId ?? this.ledgerExternalId,
      entityType: entityType ?? this.entityType,
      entitySyncId: entitySyncId ?? this.entitySyncId,
      action: action ?? this.action,
      rawChangeJson: rawChangeJson ?? this.rawChangeJson,
      errorClass: errorClass ?? this.errorClass,
      errorMessage: errorMessage ?? this.errorMessage,
      stackTrace: stackTrace ?? this.stackTrace,
      firstSeenAt: firstSeenAt ?? this.firstSeenAt,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      attemptCount: attemptCount ?? this.attemptCount,
      userAction: userAction ?? this.userAction,
      resolvedAt: resolvedAt ?? this.resolvedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (changeId.present) {
      map['change_id'] = Variable<int>(changeId.value);
    }
    if (ledgerExternalId.present) {
      map['ledger_external_id'] = Variable<String>(ledgerExternalId.value);
    }
    if (entityType.present) {
      map['entity_type'] = Variable<String>(entityType.value);
    }
    if (entitySyncId.present) {
      map['entity_sync_id'] = Variable<String>(entitySyncId.value);
    }
    if (action.present) {
      map['action'] = Variable<String>(action.value);
    }
    if (rawChangeJson.present) {
      map['raw_change_json'] = Variable<String>(rawChangeJson.value);
    }
    if (errorClass.present) {
      map['error_class'] = Variable<String>(errorClass.value);
    }
    if (errorMessage.present) {
      map['error_message'] = Variable<String>(errorMessage.value);
    }
    if (stackTrace.present) {
      map['stack_trace'] = Variable<String>(stackTrace.value);
    }
    if (firstSeenAt.present) {
      map['first_seen_at'] = Variable<DateTime>(firstSeenAt.value);
    }
    if (lastAttemptAt.present) {
      map['last_attempt_at'] = Variable<DateTime>(lastAttemptAt.value);
    }
    if (attemptCount.present) {
      map['attempt_count'] = Variable<int>(attemptCount.value);
    }
    if (userAction.present) {
      map['user_action'] = Variable<String>(userAction.value);
    }
    if (resolvedAt.present) {
      map['resolved_at'] = Variable<DateTime>(resolvedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncPullErrorsCompanion(')
          ..write('id: $id, ')
          ..write('changeId: $changeId, ')
          ..write('ledgerExternalId: $ledgerExternalId, ')
          ..write('entityType: $entityType, ')
          ..write('entitySyncId: $entitySyncId, ')
          ..write('action: $action, ')
          ..write('rawChangeJson: $rawChangeJson, ')
          ..write('errorClass: $errorClass, ')
          ..write('errorMessage: $errorMessage, ')
          ..write('stackTrace: $stackTrace, ')
          ..write('firstSeenAt: $firstSeenAt, ')
          ..write('lastAttemptAt: $lastAttemptAt, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('userAction: $userAction, ')
          ..write('resolvedAt: $resolvedAt')
          ..write(')'))
        .toString();
  }
}

class $ExchangeRatesTable extends ExchangeRates
    with TableInfo<$ExchangeRatesTable, ExchangeRate> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ExchangeRatesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _baseCurrencyMeta =
      const VerificationMeta('baseCurrency');
  @override
  late final GeneratedColumn<String> baseCurrency = GeneratedColumn<String>(
      'base_currency', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _quoteCurrencyMeta =
      const VerificationMeta('quoteCurrency');
  @override
  late final GeneratedColumn<String> quoteCurrency = GeneratedColumn<String>(
      'quote_currency', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _rateDateMeta =
      const VerificationMeta('rateDate');
  @override
  late final GeneratedColumn<String> rateDate = GeneratedColumn<String>(
      'rate_date', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _rateMeta = const VerificationMeta('rate');
  @override
  late final GeneratedColumn<String> rate = GeneratedColumn<String>(
      'rate', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
      'source', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _fetchedAtMeta =
      const VerificationMeta('fetchedAt');
  @override
  late final GeneratedColumn<DateTime> fetchedAt = GeneratedColumn<DateTime>(
      'fetched_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [baseCurrency, quoteCurrency, rateDate, rate, source, fetchedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'exchange_rates';
  @override
  VerificationContext validateIntegrity(Insertable<ExchangeRate> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('base_currency')) {
      context.handle(
          _baseCurrencyMeta,
          baseCurrency.isAcceptableOrUnknown(
              data['base_currency']!, _baseCurrencyMeta));
    } else if (isInserting) {
      context.missing(_baseCurrencyMeta);
    }
    if (data.containsKey('quote_currency')) {
      context.handle(
          _quoteCurrencyMeta,
          quoteCurrency.isAcceptableOrUnknown(
              data['quote_currency']!, _quoteCurrencyMeta));
    } else if (isInserting) {
      context.missing(_quoteCurrencyMeta);
    }
    if (data.containsKey('rate_date')) {
      context.handle(_rateDateMeta,
          rateDate.isAcceptableOrUnknown(data['rate_date']!, _rateDateMeta));
    } else if (isInserting) {
      context.missing(_rateDateMeta);
    }
    if (data.containsKey('rate')) {
      context.handle(
          _rateMeta, rate.isAcceptableOrUnknown(data['rate']!, _rateMeta));
    } else if (isInserting) {
      context.missing(_rateMeta);
    }
    if (data.containsKey('source')) {
      context.handle(_sourceMeta,
          source.isAcceptableOrUnknown(data['source']!, _sourceMeta));
    } else if (isInserting) {
      context.missing(_sourceMeta);
    }
    if (data.containsKey('fetched_at')) {
      context.handle(_fetchedAtMeta,
          fetchedAt.isAcceptableOrUnknown(data['fetched_at']!, _fetchedAtMeta));
    } else if (isInserting) {
      context.missing(_fetchedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey =>
      {baseCurrency, quoteCurrency, rateDate};
  @override
  ExchangeRate map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ExchangeRate(
      baseCurrency: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}base_currency'])!,
      quoteCurrency: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}quote_currency'])!,
      rateDate: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}rate_date'])!,
      rate: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}rate'])!,
      source: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}source'])!,
      fetchedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}fetched_at'])!,
    );
  }

  @override
  $ExchangeRatesTable createAlias(String alias) {
    return $ExchangeRatesTable(attachedDatabase, alias);
  }
}

class ExchangeRate extends DataClass implements Insertable<ExchangeRate> {
  final String baseCurrency;
  final String quoteCurrency;
  final String rateDate;
  final String rate;
  final String source;
  final DateTime fetchedAt;
  const ExchangeRate(
      {required this.baseCurrency,
      required this.quoteCurrency,
      required this.rateDate,
      required this.rate,
      required this.source,
      required this.fetchedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['base_currency'] = Variable<String>(baseCurrency);
    map['quote_currency'] = Variable<String>(quoteCurrency);
    map['rate_date'] = Variable<String>(rateDate);
    map['rate'] = Variable<String>(rate);
    map['source'] = Variable<String>(source);
    map['fetched_at'] = Variable<DateTime>(fetchedAt);
    return map;
  }

  ExchangeRatesCompanion toCompanion(bool nullToAbsent) {
    return ExchangeRatesCompanion(
      baseCurrency: Value(baseCurrency),
      quoteCurrency: Value(quoteCurrency),
      rateDate: Value(rateDate),
      rate: Value(rate),
      source: Value(source),
      fetchedAt: Value(fetchedAt),
    );
  }

  factory ExchangeRate.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ExchangeRate(
      baseCurrency: serializer.fromJson<String>(json['baseCurrency']),
      quoteCurrency: serializer.fromJson<String>(json['quoteCurrency']),
      rateDate: serializer.fromJson<String>(json['rateDate']),
      rate: serializer.fromJson<String>(json['rate']),
      source: serializer.fromJson<String>(json['source']),
      fetchedAt: serializer.fromJson<DateTime>(json['fetchedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'baseCurrency': serializer.toJson<String>(baseCurrency),
      'quoteCurrency': serializer.toJson<String>(quoteCurrency),
      'rateDate': serializer.toJson<String>(rateDate),
      'rate': serializer.toJson<String>(rate),
      'source': serializer.toJson<String>(source),
      'fetchedAt': serializer.toJson<DateTime>(fetchedAt),
    };
  }

  ExchangeRate copyWith(
          {String? baseCurrency,
          String? quoteCurrency,
          String? rateDate,
          String? rate,
          String? source,
          DateTime? fetchedAt}) =>
      ExchangeRate(
        baseCurrency: baseCurrency ?? this.baseCurrency,
        quoteCurrency: quoteCurrency ?? this.quoteCurrency,
        rateDate: rateDate ?? this.rateDate,
        rate: rate ?? this.rate,
        source: source ?? this.source,
        fetchedAt: fetchedAt ?? this.fetchedAt,
      );
  ExchangeRate copyWithCompanion(ExchangeRatesCompanion data) {
    return ExchangeRate(
      baseCurrency: data.baseCurrency.present
          ? data.baseCurrency.value
          : this.baseCurrency,
      quoteCurrency: data.quoteCurrency.present
          ? data.quoteCurrency.value
          : this.quoteCurrency,
      rateDate: data.rateDate.present ? data.rateDate.value : this.rateDate,
      rate: data.rate.present ? data.rate.value : this.rate,
      source: data.source.present ? data.source.value : this.source,
      fetchedAt: data.fetchedAt.present ? data.fetchedAt.value : this.fetchedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ExchangeRate(')
          ..write('baseCurrency: $baseCurrency, ')
          ..write('quoteCurrency: $quoteCurrency, ')
          ..write('rateDate: $rateDate, ')
          ..write('rate: $rate, ')
          ..write('source: $source, ')
          ..write('fetchedAt: $fetchedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      baseCurrency, quoteCurrency, rateDate, rate, source, fetchedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ExchangeRate &&
          other.baseCurrency == this.baseCurrency &&
          other.quoteCurrency == this.quoteCurrency &&
          other.rateDate == this.rateDate &&
          other.rate == this.rate &&
          other.source == this.source &&
          other.fetchedAt == this.fetchedAt);
}

class ExchangeRatesCompanion extends UpdateCompanion<ExchangeRate> {
  final Value<String> baseCurrency;
  final Value<String> quoteCurrency;
  final Value<String> rateDate;
  final Value<String> rate;
  final Value<String> source;
  final Value<DateTime> fetchedAt;
  final Value<int> rowid;
  const ExchangeRatesCompanion({
    this.baseCurrency = const Value.absent(),
    this.quoteCurrency = const Value.absent(),
    this.rateDate = const Value.absent(),
    this.rate = const Value.absent(),
    this.source = const Value.absent(),
    this.fetchedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ExchangeRatesCompanion.insert({
    required String baseCurrency,
    required String quoteCurrency,
    required String rateDate,
    required String rate,
    required String source,
    required DateTime fetchedAt,
    this.rowid = const Value.absent(),
  })  : baseCurrency = Value(baseCurrency),
        quoteCurrency = Value(quoteCurrency),
        rateDate = Value(rateDate),
        rate = Value(rate),
        source = Value(source),
        fetchedAt = Value(fetchedAt);
  static Insertable<ExchangeRate> custom({
    Expression<String>? baseCurrency,
    Expression<String>? quoteCurrency,
    Expression<String>? rateDate,
    Expression<String>? rate,
    Expression<String>? source,
    Expression<DateTime>? fetchedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (baseCurrency != null) 'base_currency': baseCurrency,
      if (quoteCurrency != null) 'quote_currency': quoteCurrency,
      if (rateDate != null) 'rate_date': rateDate,
      if (rate != null) 'rate': rate,
      if (source != null) 'source': source,
      if (fetchedAt != null) 'fetched_at': fetchedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ExchangeRatesCompanion copyWith(
      {Value<String>? baseCurrency,
      Value<String>? quoteCurrency,
      Value<String>? rateDate,
      Value<String>? rate,
      Value<String>? source,
      Value<DateTime>? fetchedAt,
      Value<int>? rowid}) {
    return ExchangeRatesCompanion(
      baseCurrency: baseCurrency ?? this.baseCurrency,
      quoteCurrency: quoteCurrency ?? this.quoteCurrency,
      rateDate: rateDate ?? this.rateDate,
      rate: rate ?? this.rate,
      source: source ?? this.source,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (baseCurrency.present) {
      map['base_currency'] = Variable<String>(baseCurrency.value);
    }
    if (quoteCurrency.present) {
      map['quote_currency'] = Variable<String>(quoteCurrency.value);
    }
    if (rateDate.present) {
      map['rate_date'] = Variable<String>(rateDate.value);
    }
    if (rate.present) {
      map['rate'] = Variable<String>(rate.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (fetchedAt.present) {
      map['fetched_at'] = Variable<DateTime>(fetchedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ExchangeRatesCompanion(')
          ..write('baseCurrency: $baseCurrency, ')
          ..write('quoteCurrency: $quoteCurrency, ')
          ..write('rateDate: $rateDate, ')
          ..write('rate: $rate, ')
          ..write('source: $source, ')
          ..write('fetchedAt: $fetchedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ExchangeRateOverridesTable extends ExchangeRateOverrides
    with TableInfo<$ExchangeRateOverridesTable, ExchangeRateOverride> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ExchangeRateOverridesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _syncIdMeta = const VerificationMeta('syncId');
  @override
  late final GeneratedColumn<String> syncId = GeneratedColumn<String>(
      'sync_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _baseCurrencyMeta =
      const VerificationMeta('baseCurrency');
  @override
  late final GeneratedColumn<String> baseCurrency = GeneratedColumn<String>(
      'base_currency', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _quoteCurrencyMeta =
      const VerificationMeta('quoteCurrency');
  @override
  late final GeneratedColumn<String> quoteCurrency = GeneratedColumn<String>(
      'quote_currency', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _rateMeta = const VerificationMeta('rate');
  @override
  late final GeneratedColumn<String> rate = GeneratedColumn<String>(
      'rate', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns =>
      [id, syncId, baseCurrency, quoteCurrency, rate, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'exchange_rate_overrides';
  @override
  VerificationContext validateIntegrity(
      Insertable<ExchangeRateOverride> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('sync_id')) {
      context.handle(_syncIdMeta,
          syncId.isAcceptableOrUnknown(data['sync_id']!, _syncIdMeta));
    }
    if (data.containsKey('base_currency')) {
      context.handle(
          _baseCurrencyMeta,
          baseCurrency.isAcceptableOrUnknown(
              data['base_currency']!, _baseCurrencyMeta));
    } else if (isInserting) {
      context.missing(_baseCurrencyMeta);
    }
    if (data.containsKey('quote_currency')) {
      context.handle(
          _quoteCurrencyMeta,
          quoteCurrency.isAcceptableOrUnknown(
              data['quote_currency']!, _quoteCurrencyMeta));
    } else if (isInserting) {
      context.missing(_quoteCurrencyMeta);
    }
    if (data.containsKey('rate')) {
      context.handle(
          _rateMeta, rate.isAcceptableOrUnknown(data['rate']!, _rateMeta));
    } else if (isInserting) {
      context.missing(_rateMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ExchangeRateOverride map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ExchangeRateOverride(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      syncId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}sync_id']),
      baseCurrency: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}base_currency'])!,
      quoteCurrency: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}quote_currency'])!,
      rate: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}rate'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at']),
    );
  }

  @override
  $ExchangeRateOverridesTable createAlias(String alias) {
    return $ExchangeRateOverridesTable(attachedDatabase, alias);
  }
}

class ExchangeRateOverride extends DataClass
    implements Insertable<ExchangeRateOverride> {
  final int id;
  final String? syncId;
  final String baseCurrency;
  final String quoteCurrency;
  final String rate;
  final DateTime? updatedAt;
  const ExchangeRateOverride(
      {required this.id,
      this.syncId,
      required this.baseCurrency,
      required this.quoteCurrency,
      required this.rate,
      this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || syncId != null) {
      map['sync_id'] = Variable<String>(syncId);
    }
    map['base_currency'] = Variable<String>(baseCurrency);
    map['quote_currency'] = Variable<String>(quoteCurrency);
    map['rate'] = Variable<String>(rate);
    if (!nullToAbsent || updatedAt != null) {
      map['updated_at'] = Variable<DateTime>(updatedAt);
    }
    return map;
  }

  ExchangeRateOverridesCompanion toCompanion(bool nullToAbsent) {
    return ExchangeRateOverridesCompanion(
      id: Value(id),
      syncId:
          syncId == null && nullToAbsent ? const Value.absent() : Value(syncId),
      baseCurrency: Value(baseCurrency),
      quoteCurrency: Value(quoteCurrency),
      rate: Value(rate),
      updatedAt: updatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(updatedAt),
    );
  }

  factory ExchangeRateOverride.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ExchangeRateOverride(
      id: serializer.fromJson<int>(json['id']),
      syncId: serializer.fromJson<String?>(json['syncId']),
      baseCurrency: serializer.fromJson<String>(json['baseCurrency']),
      quoteCurrency: serializer.fromJson<String>(json['quoteCurrency']),
      rate: serializer.fromJson<String>(json['rate']),
      updatedAt: serializer.fromJson<DateTime?>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'syncId': serializer.toJson<String?>(syncId),
      'baseCurrency': serializer.toJson<String>(baseCurrency),
      'quoteCurrency': serializer.toJson<String>(quoteCurrency),
      'rate': serializer.toJson<String>(rate),
      'updatedAt': serializer.toJson<DateTime?>(updatedAt),
    };
  }

  ExchangeRateOverride copyWith(
          {int? id,
          Value<String?> syncId = const Value.absent(),
          String? baseCurrency,
          String? quoteCurrency,
          String? rate,
          Value<DateTime?> updatedAt = const Value.absent()}) =>
      ExchangeRateOverride(
        id: id ?? this.id,
        syncId: syncId.present ? syncId.value : this.syncId,
        baseCurrency: baseCurrency ?? this.baseCurrency,
        quoteCurrency: quoteCurrency ?? this.quoteCurrency,
        rate: rate ?? this.rate,
        updatedAt: updatedAt.present ? updatedAt.value : this.updatedAt,
      );
  ExchangeRateOverride copyWithCompanion(ExchangeRateOverridesCompanion data) {
    return ExchangeRateOverride(
      id: data.id.present ? data.id.value : this.id,
      syncId: data.syncId.present ? data.syncId.value : this.syncId,
      baseCurrency: data.baseCurrency.present
          ? data.baseCurrency.value
          : this.baseCurrency,
      quoteCurrency: data.quoteCurrency.present
          ? data.quoteCurrency.value
          : this.quoteCurrency,
      rate: data.rate.present ? data.rate.value : this.rate,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ExchangeRateOverride(')
          ..write('id: $id, ')
          ..write('syncId: $syncId, ')
          ..write('baseCurrency: $baseCurrency, ')
          ..write('quoteCurrency: $quoteCurrency, ')
          ..write('rate: $rate, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, syncId, baseCurrency, quoteCurrency, rate, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ExchangeRateOverride &&
          other.id == this.id &&
          other.syncId == this.syncId &&
          other.baseCurrency == this.baseCurrency &&
          other.quoteCurrency == this.quoteCurrency &&
          other.rate == this.rate &&
          other.updatedAt == this.updatedAt);
}

class ExchangeRateOverridesCompanion
    extends UpdateCompanion<ExchangeRateOverride> {
  final Value<int> id;
  final Value<String?> syncId;
  final Value<String> baseCurrency;
  final Value<String> quoteCurrency;
  final Value<String> rate;
  final Value<DateTime?> updatedAt;
  const ExchangeRateOverridesCompanion({
    this.id = const Value.absent(),
    this.syncId = const Value.absent(),
    this.baseCurrency = const Value.absent(),
    this.quoteCurrency = const Value.absent(),
    this.rate = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  ExchangeRateOverridesCompanion.insert({
    this.id = const Value.absent(),
    this.syncId = const Value.absent(),
    required String baseCurrency,
    required String quoteCurrency,
    required String rate,
    this.updatedAt = const Value.absent(),
  })  : baseCurrency = Value(baseCurrency),
        quoteCurrency = Value(quoteCurrency),
        rate = Value(rate);
  static Insertable<ExchangeRateOverride> custom({
    Expression<int>? id,
    Expression<String>? syncId,
    Expression<String>? baseCurrency,
    Expression<String>? quoteCurrency,
    Expression<String>? rate,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (syncId != null) 'sync_id': syncId,
      if (baseCurrency != null) 'base_currency': baseCurrency,
      if (quoteCurrency != null) 'quote_currency': quoteCurrency,
      if (rate != null) 'rate': rate,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  ExchangeRateOverridesCompanion copyWith(
      {Value<int>? id,
      Value<String?>? syncId,
      Value<String>? baseCurrency,
      Value<String>? quoteCurrency,
      Value<String>? rate,
      Value<DateTime?>? updatedAt}) {
    return ExchangeRateOverridesCompanion(
      id: id ?? this.id,
      syncId: syncId ?? this.syncId,
      baseCurrency: baseCurrency ?? this.baseCurrency,
      quoteCurrency: quoteCurrency ?? this.quoteCurrency,
      rate: rate ?? this.rate,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (syncId.present) {
      map['sync_id'] = Variable<String>(syncId.value);
    }
    if (baseCurrency.present) {
      map['base_currency'] = Variable<String>(baseCurrency.value);
    }
    if (quoteCurrency.present) {
      map['quote_currency'] = Variable<String>(quoteCurrency.value);
    }
    if (rate.present) {
      map['rate'] = Variable<String>(rate.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ExchangeRateOverridesCompanion(')
          ..write('id: $id, ')
          ..write('syncId: $syncId, ')
          ..write('baseCurrency: $baseCurrency, ')
          ..write('quoteCurrency: $quoteCurrency, ')
          ..write('rate: $rate, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $CardRewardRulesTable extends CardRewardRules
    with TableInfo<$CardRewardRulesTable, CardRewardRule> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CardRewardRulesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _accountIdMeta =
      const VerificationMeta('accountId');
  @override
  late final GeneratedColumn<int> accountId = GeneratedColumn<int>(
      'account_id', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _syncIdMeta = const VerificationMeta('syncId');
  @override
  late final GeneratedColumn<String> syncId = GeneratedColumn<String>(
      'sync_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _labelMeta = const VerificationMeta('label');
  @override
  late final GeneratedColumn<String> label = GeneratedColumn<String>(
      'label', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _categoryIdsJsonMeta =
      const VerificationMeta('categoryIdsJson');
  @override
  late final GeneratedColumn<String> categoryIdsJson = GeneratedColumn<String>(
      'category_ids_json', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _rateTypeMeta =
      const VerificationMeta('rateType');
  @override
  late final GeneratedColumn<String> rateType = GeneratedColumn<String>(
      'rate_type', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('percentage'));
  static const VerificationMeta _rateValueMeta =
      const VerificationMeta('rateValue');
  @override
  late final GeneratedColumn<double> rateValue = GeneratedColumn<double>(
      'rate_value', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _roundingMeta =
      const VerificationMeta('rounding');
  @override
  late final GeneratedColumn<String> rounding = GeneratedColumn<String>(
      'rounding', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('round'));
  static const VerificationMeta _totalRoundingMeta =
      const VerificationMeta('totalRounding');
  @override
  late final GeneratedColumn<String> totalRounding = GeneratedColumn<String>(
      'total_rounding', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('round'));
  static const VerificationMeta _calcBasisMeta =
      const VerificationMeta('calcBasis');
  @override
  late final GeneratedColumn<String> calcBasis = GeneratedColumn<String>(
      'calc_basis', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('transaction_date'));
  static const VerificationMeta _intervalMeta =
      const VerificationMeta('interval');
  @override
  late final GeneratedColumn<String> interval = GeneratedColumn<String>(
      'interval', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('billing_cycle'));
  static const VerificationMeta _minSpendThresholdMeta =
      const VerificationMeta('minSpendThreshold');
  @override
  late final GeneratedColumn<double> minSpendThreshold =
      GeneratedColumn<double>('min_spend_threshold', aliasedName, true,
          type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _minTxAmountMeta =
      const VerificationMeta('minTxAmount');
  @override
  late final GeneratedColumn<double> minTxAmount = GeneratedColumn<double>(
      'min_tx_amount', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _capAmountMeta =
      const VerificationMeta('capAmount');
  @override
  late final GeneratedColumn<double> capAmount = GeneratedColumn<double>(
      'cap_amount', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _capSharedKeyMeta =
      const VerificationMeta('capSharedKey');
  @override
  late final GeneratedColumn<String> capSharedKey = GeneratedColumn<String>(
      'cap_shared_key', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _startsAtMeta =
      const VerificationMeta('startsAt');
  @override
  late final GeneratedColumn<DateTime> startsAt = GeneratedColumn<DateTime>(
      'starts_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _endsAtMeta = const VerificationMeta('endsAt');
  @override
  late final GeneratedColumn<DateTime> endsAt = GeneratedColumn<DateTime>(
      'ends_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _settlementTypeMeta =
      const VerificationMeta('settlementType');
  @override
  late final GeneratedColumn<String> settlementType = GeneratedColumn<String>(
      'settlement_type', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('manual'));
  static const VerificationMeta _settlementDaysMeta =
      const VerificationMeta('settlementDays');
  @override
  late final GeneratedColumn<int> settlementDays = GeneratedColumn<int>(
      'settlement_days', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _settlementMonthOffsetMeta =
      const VerificationMeta('settlementMonthOffset');
  @override
  late final GeneratedColumn<int> settlementMonthOffset = GeneratedColumn<int>(
      'settlement_month_offset', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _settlementDayOfMonthMeta =
      const VerificationMeta('settlementDayOfMonth');
  @override
  late final GeneratedColumn<int> settlementDayOfMonth = GeneratedColumn<int>(
      'settlement_day_of_month', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _rewardAccountIdMeta =
      const VerificationMeta('rewardAccountId');
  @override
  late final GeneratedColumn<int> rewardAccountId = GeneratedColumn<int>(
      'reward_account_id', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
      'note', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _enabledMeta =
      const VerificationMeta('enabled');
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
      'enabled', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("enabled" IN (0, 1))'),
      defaultValue: const Constant(true));
  static const VerificationMeta _sortOrderMeta =
      const VerificationMeta('sortOrder');
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
      'sort_order', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        accountId,
        syncId,
        label,
        categoryIdsJson,
        rateType,
        rateValue,
        rounding,
        totalRounding,
        calcBasis,
        interval,
        minSpendThreshold,
        minTxAmount,
        capAmount,
        capSharedKey,
        startsAt,
        endsAt,
        settlementType,
        settlementDays,
        settlementMonthOffset,
        settlementDayOfMonth,
        rewardAccountId,
        note,
        enabled,
        sortOrder,
        createdAt,
        updatedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'card_reward_rules';
  @override
  VerificationContext validateIntegrity(Insertable<CardRewardRule> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('account_id')) {
      context.handle(_accountIdMeta,
          accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta));
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('sync_id')) {
      context.handle(_syncIdMeta,
          syncId.isAcceptableOrUnknown(data['sync_id']!, _syncIdMeta));
    }
    if (data.containsKey('label')) {
      context.handle(
          _labelMeta, label.isAcceptableOrUnknown(data['label']!, _labelMeta));
    } else if (isInserting) {
      context.missing(_labelMeta);
    }
    if (data.containsKey('category_ids_json')) {
      context.handle(
          _categoryIdsJsonMeta,
          categoryIdsJson.isAcceptableOrUnknown(
              data['category_ids_json']!, _categoryIdsJsonMeta));
    }
    if (data.containsKey('rate_type')) {
      context.handle(_rateTypeMeta,
          rateType.isAcceptableOrUnknown(data['rate_type']!, _rateTypeMeta));
    }
    if (data.containsKey('rate_value')) {
      context.handle(_rateValueMeta,
          rateValue.isAcceptableOrUnknown(data['rate_value']!, _rateValueMeta));
    } else if (isInserting) {
      context.missing(_rateValueMeta);
    }
    if (data.containsKey('rounding')) {
      context.handle(_roundingMeta,
          rounding.isAcceptableOrUnknown(data['rounding']!, _roundingMeta));
    }
    if (data.containsKey('total_rounding')) {
      context.handle(
          _totalRoundingMeta,
          totalRounding.isAcceptableOrUnknown(
              data['total_rounding']!, _totalRoundingMeta));
    }
    if (data.containsKey('calc_basis')) {
      context.handle(_calcBasisMeta,
          calcBasis.isAcceptableOrUnknown(data['calc_basis']!, _calcBasisMeta));
    }
    if (data.containsKey('interval')) {
      context.handle(_intervalMeta,
          interval.isAcceptableOrUnknown(data['interval']!, _intervalMeta));
    }
    if (data.containsKey('min_spend_threshold')) {
      context.handle(
          _minSpendThresholdMeta,
          minSpendThreshold.isAcceptableOrUnknown(
              data['min_spend_threshold']!, _minSpendThresholdMeta));
    }
    if (data.containsKey('min_tx_amount')) {
      context.handle(
          _minTxAmountMeta,
          minTxAmount.isAcceptableOrUnknown(
              data['min_tx_amount']!, _minTxAmountMeta));
    }
    if (data.containsKey('cap_amount')) {
      context.handle(_capAmountMeta,
          capAmount.isAcceptableOrUnknown(data['cap_amount']!, _capAmountMeta));
    }
    if (data.containsKey('cap_shared_key')) {
      context.handle(
          _capSharedKeyMeta,
          capSharedKey.isAcceptableOrUnknown(
              data['cap_shared_key']!, _capSharedKeyMeta));
    }
    if (data.containsKey('starts_at')) {
      context.handle(_startsAtMeta,
          startsAt.isAcceptableOrUnknown(data['starts_at']!, _startsAtMeta));
    }
    if (data.containsKey('ends_at')) {
      context.handle(_endsAtMeta,
          endsAt.isAcceptableOrUnknown(data['ends_at']!, _endsAtMeta));
    }
    if (data.containsKey('settlement_type')) {
      context.handle(
          _settlementTypeMeta,
          settlementType.isAcceptableOrUnknown(
              data['settlement_type']!, _settlementTypeMeta));
    }
    if (data.containsKey('settlement_days')) {
      context.handle(
          _settlementDaysMeta,
          settlementDays.isAcceptableOrUnknown(
              data['settlement_days']!, _settlementDaysMeta));
    }
    if (data.containsKey('settlement_month_offset')) {
      context.handle(
          _settlementMonthOffsetMeta,
          settlementMonthOffset.isAcceptableOrUnknown(
              data['settlement_month_offset']!, _settlementMonthOffsetMeta));
    }
    if (data.containsKey('settlement_day_of_month')) {
      context.handle(
          _settlementDayOfMonthMeta,
          settlementDayOfMonth.isAcceptableOrUnknown(
              data['settlement_day_of_month']!, _settlementDayOfMonthMeta));
    }
    if (data.containsKey('reward_account_id')) {
      context.handle(
          _rewardAccountIdMeta,
          rewardAccountId.isAcceptableOrUnknown(
              data['reward_account_id']!, _rewardAccountIdMeta));
    }
    if (data.containsKey('note')) {
      context.handle(
          _noteMeta, note.isAcceptableOrUnknown(data['note']!, _noteMeta));
    }
    if (data.containsKey('enabled')) {
      context.handle(_enabledMeta,
          enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta));
    }
    if (data.containsKey('sort_order')) {
      context.handle(_sortOrderMeta,
          sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CardRewardRule map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CardRewardRule(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      accountId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}account_id'])!,
      syncId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}sync_id']),
      label: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}label'])!,
      categoryIdsJson: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}category_ids_json']),
      rateType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}rate_type'])!,
      rateValue: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}rate_value'])!,
      rounding: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}rounding'])!,
      totalRounding: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}total_rounding'])!,
      calcBasis: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}calc_basis'])!,
      interval: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}interval'])!,
      minSpendThreshold: attachedDatabase.typeMapping.read(
          DriftSqlType.double, data['${effectivePrefix}min_spend_threshold']),
      minTxAmount: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}min_tx_amount']),
      capAmount: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}cap_amount']),
      capSharedKey: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}cap_shared_key']),
      startsAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}starts_at']),
      endsAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}ends_at']),
      settlementType: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}settlement_type'])!,
      settlementDays: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}settlement_days']),
      settlementMonthOffset: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}settlement_month_offset']),
      settlementDayOfMonth: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}settlement_day_of_month']),
      rewardAccountId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}reward_account_id']),
      note: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}note']),
      enabled: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}enabled'])!,
      sortOrder: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}sort_order'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at']),
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at']),
    );
  }

  @override
  $CardRewardRulesTable createAlias(String alias) {
    return $CardRewardRulesTable(attachedDatabase, alias);
  }
}

class CardRewardRule extends DataClass implements Insertable<CardRewardRule> {
  final int id;

  /// 绑定的信用卡帐户(本地 int id)。server 端建立后不可改(wire 字段
  /// accountId 只在 create payload 送,update 不送这个 key)。
  final int accountId;
  final String? syncId;
  final String label;

  /// 保留字段,JSON list of category syncId。2026-08-06 起不参与回馈资格
  /// 自动比对(改成使用者记账时手动勾选 rewardRuleIds),这里纯粹用于编辑页
  /// 显示/筛选。
  final String? categoryIdsJson;
  final String rateType;
  final double rateValue;
  final String rounding;
  final String totalRounding;
  final String calcBasis;
  final String interval;
  final double? minSpendThreshold;
  final double? minTxAmount;
  final double? capAmount;
  final String? capSharedKey;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final String settlementType;
  final int? settlementDays;
  final int? settlementMonthOffset;
  final int? settlementDayOfMonth;

  /// 回饋入帳帐户(本地 int id,nullable——manual 结算类型允许不设)。
  final int? rewardAccountId;
  final String? note;
  final bool enabled;
  final int sortOrder;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  const CardRewardRule(
      {required this.id,
      required this.accountId,
      this.syncId,
      required this.label,
      this.categoryIdsJson,
      required this.rateType,
      required this.rateValue,
      required this.rounding,
      required this.totalRounding,
      required this.calcBasis,
      required this.interval,
      this.minSpendThreshold,
      this.minTxAmount,
      this.capAmount,
      this.capSharedKey,
      this.startsAt,
      this.endsAt,
      required this.settlementType,
      this.settlementDays,
      this.settlementMonthOffset,
      this.settlementDayOfMonth,
      this.rewardAccountId,
      this.note,
      required this.enabled,
      required this.sortOrder,
      this.createdAt,
      this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['account_id'] = Variable<int>(accountId);
    if (!nullToAbsent || syncId != null) {
      map['sync_id'] = Variable<String>(syncId);
    }
    map['label'] = Variable<String>(label);
    if (!nullToAbsent || categoryIdsJson != null) {
      map['category_ids_json'] = Variable<String>(categoryIdsJson);
    }
    map['rate_type'] = Variable<String>(rateType);
    map['rate_value'] = Variable<double>(rateValue);
    map['rounding'] = Variable<String>(rounding);
    map['total_rounding'] = Variable<String>(totalRounding);
    map['calc_basis'] = Variable<String>(calcBasis);
    map['interval'] = Variable<String>(interval);
    if (!nullToAbsent || minSpendThreshold != null) {
      map['min_spend_threshold'] = Variable<double>(minSpendThreshold);
    }
    if (!nullToAbsent || minTxAmount != null) {
      map['min_tx_amount'] = Variable<double>(minTxAmount);
    }
    if (!nullToAbsent || capAmount != null) {
      map['cap_amount'] = Variable<double>(capAmount);
    }
    if (!nullToAbsent || capSharedKey != null) {
      map['cap_shared_key'] = Variable<String>(capSharedKey);
    }
    if (!nullToAbsent || startsAt != null) {
      map['starts_at'] = Variable<DateTime>(startsAt);
    }
    if (!nullToAbsent || endsAt != null) {
      map['ends_at'] = Variable<DateTime>(endsAt);
    }
    map['settlement_type'] = Variable<String>(settlementType);
    if (!nullToAbsent || settlementDays != null) {
      map['settlement_days'] = Variable<int>(settlementDays);
    }
    if (!nullToAbsent || settlementMonthOffset != null) {
      map['settlement_month_offset'] = Variable<int>(settlementMonthOffset);
    }
    if (!nullToAbsent || settlementDayOfMonth != null) {
      map['settlement_day_of_month'] = Variable<int>(settlementDayOfMonth);
    }
    if (!nullToAbsent || rewardAccountId != null) {
      map['reward_account_id'] = Variable<int>(rewardAccountId);
    }
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    map['enabled'] = Variable<bool>(enabled);
    map['sort_order'] = Variable<int>(sortOrder);
    if (!nullToAbsent || createdAt != null) {
      map['created_at'] = Variable<DateTime>(createdAt);
    }
    if (!nullToAbsent || updatedAt != null) {
      map['updated_at'] = Variable<DateTime>(updatedAt);
    }
    return map;
  }

  CardRewardRulesCompanion toCompanion(bool nullToAbsent) {
    return CardRewardRulesCompanion(
      id: Value(id),
      accountId: Value(accountId),
      syncId:
          syncId == null && nullToAbsent ? const Value.absent() : Value(syncId),
      label: Value(label),
      categoryIdsJson: categoryIdsJson == null && nullToAbsent
          ? const Value.absent()
          : Value(categoryIdsJson),
      rateType: Value(rateType),
      rateValue: Value(rateValue),
      rounding: Value(rounding),
      totalRounding: Value(totalRounding),
      calcBasis: Value(calcBasis),
      interval: Value(interval),
      minSpendThreshold: minSpendThreshold == null && nullToAbsent
          ? const Value.absent()
          : Value(minSpendThreshold),
      minTxAmount: minTxAmount == null && nullToAbsent
          ? const Value.absent()
          : Value(minTxAmount),
      capAmount: capAmount == null && nullToAbsent
          ? const Value.absent()
          : Value(capAmount),
      capSharedKey: capSharedKey == null && nullToAbsent
          ? const Value.absent()
          : Value(capSharedKey),
      startsAt: startsAt == null && nullToAbsent
          ? const Value.absent()
          : Value(startsAt),
      endsAt:
          endsAt == null && nullToAbsent ? const Value.absent() : Value(endsAt),
      settlementType: Value(settlementType),
      settlementDays: settlementDays == null && nullToAbsent
          ? const Value.absent()
          : Value(settlementDays),
      settlementMonthOffset: settlementMonthOffset == null && nullToAbsent
          ? const Value.absent()
          : Value(settlementMonthOffset),
      settlementDayOfMonth: settlementDayOfMonth == null && nullToAbsent
          ? const Value.absent()
          : Value(settlementDayOfMonth),
      rewardAccountId: rewardAccountId == null && nullToAbsent
          ? const Value.absent()
          : Value(rewardAccountId),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      enabled: Value(enabled),
      sortOrder: Value(sortOrder),
      createdAt: createdAt == null && nullToAbsent
          ? const Value.absent()
          : Value(createdAt),
      updatedAt: updatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(updatedAt),
    );
  }

  factory CardRewardRule.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CardRewardRule(
      id: serializer.fromJson<int>(json['id']),
      accountId: serializer.fromJson<int>(json['accountId']),
      syncId: serializer.fromJson<String?>(json['syncId']),
      label: serializer.fromJson<String>(json['label']),
      categoryIdsJson: serializer.fromJson<String?>(json['categoryIdsJson']),
      rateType: serializer.fromJson<String>(json['rateType']),
      rateValue: serializer.fromJson<double>(json['rateValue']),
      rounding: serializer.fromJson<String>(json['rounding']),
      totalRounding: serializer.fromJson<String>(json['totalRounding']),
      calcBasis: serializer.fromJson<String>(json['calcBasis']),
      interval: serializer.fromJson<String>(json['interval']),
      minSpendThreshold:
          serializer.fromJson<double?>(json['minSpendThreshold']),
      minTxAmount: serializer.fromJson<double?>(json['minTxAmount']),
      capAmount: serializer.fromJson<double?>(json['capAmount']),
      capSharedKey: serializer.fromJson<String?>(json['capSharedKey']),
      startsAt: serializer.fromJson<DateTime?>(json['startsAt']),
      endsAt: serializer.fromJson<DateTime?>(json['endsAt']),
      settlementType: serializer.fromJson<String>(json['settlementType']),
      settlementDays: serializer.fromJson<int?>(json['settlementDays']),
      settlementMonthOffset:
          serializer.fromJson<int?>(json['settlementMonthOffset']),
      settlementDayOfMonth:
          serializer.fromJson<int?>(json['settlementDayOfMonth']),
      rewardAccountId: serializer.fromJson<int?>(json['rewardAccountId']),
      note: serializer.fromJson<String?>(json['note']),
      enabled: serializer.fromJson<bool>(json['enabled']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      createdAt: serializer.fromJson<DateTime?>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime?>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'accountId': serializer.toJson<int>(accountId),
      'syncId': serializer.toJson<String?>(syncId),
      'label': serializer.toJson<String>(label),
      'categoryIdsJson': serializer.toJson<String?>(categoryIdsJson),
      'rateType': serializer.toJson<String>(rateType),
      'rateValue': serializer.toJson<double>(rateValue),
      'rounding': serializer.toJson<String>(rounding),
      'totalRounding': serializer.toJson<String>(totalRounding),
      'calcBasis': serializer.toJson<String>(calcBasis),
      'interval': serializer.toJson<String>(interval),
      'minSpendThreshold': serializer.toJson<double?>(minSpendThreshold),
      'minTxAmount': serializer.toJson<double?>(minTxAmount),
      'capAmount': serializer.toJson<double?>(capAmount),
      'capSharedKey': serializer.toJson<String?>(capSharedKey),
      'startsAt': serializer.toJson<DateTime?>(startsAt),
      'endsAt': serializer.toJson<DateTime?>(endsAt),
      'settlementType': serializer.toJson<String>(settlementType),
      'settlementDays': serializer.toJson<int?>(settlementDays),
      'settlementMonthOffset': serializer.toJson<int?>(settlementMonthOffset),
      'settlementDayOfMonth': serializer.toJson<int?>(settlementDayOfMonth),
      'rewardAccountId': serializer.toJson<int?>(rewardAccountId),
      'note': serializer.toJson<String?>(note),
      'enabled': serializer.toJson<bool>(enabled),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'createdAt': serializer.toJson<DateTime?>(createdAt),
      'updatedAt': serializer.toJson<DateTime?>(updatedAt),
    };
  }

  CardRewardRule copyWith(
          {int? id,
          int? accountId,
          Value<String?> syncId = const Value.absent(),
          String? label,
          Value<String?> categoryIdsJson = const Value.absent(),
          String? rateType,
          double? rateValue,
          String? rounding,
          String? totalRounding,
          String? calcBasis,
          String? interval,
          Value<double?> minSpendThreshold = const Value.absent(),
          Value<double?> minTxAmount = const Value.absent(),
          Value<double?> capAmount = const Value.absent(),
          Value<String?> capSharedKey = const Value.absent(),
          Value<DateTime?> startsAt = const Value.absent(),
          Value<DateTime?> endsAt = const Value.absent(),
          String? settlementType,
          Value<int?> settlementDays = const Value.absent(),
          Value<int?> settlementMonthOffset = const Value.absent(),
          Value<int?> settlementDayOfMonth = const Value.absent(),
          Value<int?> rewardAccountId = const Value.absent(),
          Value<String?> note = const Value.absent(),
          bool? enabled,
          int? sortOrder,
          Value<DateTime?> createdAt = const Value.absent(),
          Value<DateTime?> updatedAt = const Value.absent()}) =>
      CardRewardRule(
        id: id ?? this.id,
        accountId: accountId ?? this.accountId,
        syncId: syncId.present ? syncId.value : this.syncId,
        label: label ?? this.label,
        categoryIdsJson: categoryIdsJson.present
            ? categoryIdsJson.value
            : this.categoryIdsJson,
        rateType: rateType ?? this.rateType,
        rateValue: rateValue ?? this.rateValue,
        rounding: rounding ?? this.rounding,
        totalRounding: totalRounding ?? this.totalRounding,
        calcBasis: calcBasis ?? this.calcBasis,
        interval: interval ?? this.interval,
        minSpendThreshold: minSpendThreshold.present
            ? minSpendThreshold.value
            : this.minSpendThreshold,
        minTxAmount: minTxAmount.present ? minTxAmount.value : this.minTxAmount,
        capAmount: capAmount.present ? capAmount.value : this.capAmount,
        capSharedKey:
            capSharedKey.present ? capSharedKey.value : this.capSharedKey,
        startsAt: startsAt.present ? startsAt.value : this.startsAt,
        endsAt: endsAt.present ? endsAt.value : this.endsAt,
        settlementType: settlementType ?? this.settlementType,
        settlementDays:
            settlementDays.present ? settlementDays.value : this.settlementDays,
        settlementMonthOffset: settlementMonthOffset.present
            ? settlementMonthOffset.value
            : this.settlementMonthOffset,
        settlementDayOfMonth: settlementDayOfMonth.present
            ? settlementDayOfMonth.value
            : this.settlementDayOfMonth,
        rewardAccountId: rewardAccountId.present
            ? rewardAccountId.value
            : this.rewardAccountId,
        note: note.present ? note.value : this.note,
        enabled: enabled ?? this.enabled,
        sortOrder: sortOrder ?? this.sortOrder,
        createdAt: createdAt.present ? createdAt.value : this.createdAt,
        updatedAt: updatedAt.present ? updatedAt.value : this.updatedAt,
      );
  CardRewardRule copyWithCompanion(CardRewardRulesCompanion data) {
    return CardRewardRule(
      id: data.id.present ? data.id.value : this.id,
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      syncId: data.syncId.present ? data.syncId.value : this.syncId,
      label: data.label.present ? data.label.value : this.label,
      categoryIdsJson: data.categoryIdsJson.present
          ? data.categoryIdsJson.value
          : this.categoryIdsJson,
      rateType: data.rateType.present ? data.rateType.value : this.rateType,
      rateValue: data.rateValue.present ? data.rateValue.value : this.rateValue,
      rounding: data.rounding.present ? data.rounding.value : this.rounding,
      totalRounding: data.totalRounding.present
          ? data.totalRounding.value
          : this.totalRounding,
      calcBasis: data.calcBasis.present ? data.calcBasis.value : this.calcBasis,
      interval: data.interval.present ? data.interval.value : this.interval,
      minSpendThreshold: data.minSpendThreshold.present
          ? data.minSpendThreshold.value
          : this.minSpendThreshold,
      minTxAmount:
          data.minTxAmount.present ? data.minTxAmount.value : this.minTxAmount,
      capAmount: data.capAmount.present ? data.capAmount.value : this.capAmount,
      capSharedKey: data.capSharedKey.present
          ? data.capSharedKey.value
          : this.capSharedKey,
      startsAt: data.startsAt.present ? data.startsAt.value : this.startsAt,
      endsAt: data.endsAt.present ? data.endsAt.value : this.endsAt,
      settlementType: data.settlementType.present
          ? data.settlementType.value
          : this.settlementType,
      settlementDays: data.settlementDays.present
          ? data.settlementDays.value
          : this.settlementDays,
      settlementMonthOffset: data.settlementMonthOffset.present
          ? data.settlementMonthOffset.value
          : this.settlementMonthOffset,
      settlementDayOfMonth: data.settlementDayOfMonth.present
          ? data.settlementDayOfMonth.value
          : this.settlementDayOfMonth,
      rewardAccountId: data.rewardAccountId.present
          ? data.rewardAccountId.value
          : this.rewardAccountId,
      note: data.note.present ? data.note.value : this.note,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CardRewardRule(')
          ..write('id: $id, ')
          ..write('accountId: $accountId, ')
          ..write('syncId: $syncId, ')
          ..write('label: $label, ')
          ..write('categoryIdsJson: $categoryIdsJson, ')
          ..write('rateType: $rateType, ')
          ..write('rateValue: $rateValue, ')
          ..write('rounding: $rounding, ')
          ..write('totalRounding: $totalRounding, ')
          ..write('calcBasis: $calcBasis, ')
          ..write('interval: $interval, ')
          ..write('minSpendThreshold: $minSpendThreshold, ')
          ..write('minTxAmount: $minTxAmount, ')
          ..write('capAmount: $capAmount, ')
          ..write('capSharedKey: $capSharedKey, ')
          ..write('startsAt: $startsAt, ')
          ..write('endsAt: $endsAt, ')
          ..write('settlementType: $settlementType, ')
          ..write('settlementDays: $settlementDays, ')
          ..write('settlementMonthOffset: $settlementMonthOffset, ')
          ..write('settlementDayOfMonth: $settlementDayOfMonth, ')
          ..write('rewardAccountId: $rewardAccountId, ')
          ..write('note: $note, ')
          ..write('enabled: $enabled, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
        id,
        accountId,
        syncId,
        label,
        categoryIdsJson,
        rateType,
        rateValue,
        rounding,
        totalRounding,
        calcBasis,
        interval,
        minSpendThreshold,
        minTxAmount,
        capAmount,
        capSharedKey,
        startsAt,
        endsAt,
        settlementType,
        settlementDays,
        settlementMonthOffset,
        settlementDayOfMonth,
        rewardAccountId,
        note,
        enabled,
        sortOrder,
        createdAt,
        updatedAt
      ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CardRewardRule &&
          other.id == this.id &&
          other.accountId == this.accountId &&
          other.syncId == this.syncId &&
          other.label == this.label &&
          other.categoryIdsJson == this.categoryIdsJson &&
          other.rateType == this.rateType &&
          other.rateValue == this.rateValue &&
          other.rounding == this.rounding &&
          other.totalRounding == this.totalRounding &&
          other.calcBasis == this.calcBasis &&
          other.interval == this.interval &&
          other.minSpendThreshold == this.minSpendThreshold &&
          other.minTxAmount == this.minTxAmount &&
          other.capAmount == this.capAmount &&
          other.capSharedKey == this.capSharedKey &&
          other.startsAt == this.startsAt &&
          other.endsAt == this.endsAt &&
          other.settlementType == this.settlementType &&
          other.settlementDays == this.settlementDays &&
          other.settlementMonthOffset == this.settlementMonthOffset &&
          other.settlementDayOfMonth == this.settlementDayOfMonth &&
          other.rewardAccountId == this.rewardAccountId &&
          other.note == this.note &&
          other.enabled == this.enabled &&
          other.sortOrder == this.sortOrder &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class CardRewardRulesCompanion extends UpdateCompanion<CardRewardRule> {
  final Value<int> id;
  final Value<int> accountId;
  final Value<String?> syncId;
  final Value<String> label;
  final Value<String?> categoryIdsJson;
  final Value<String> rateType;
  final Value<double> rateValue;
  final Value<String> rounding;
  final Value<String> totalRounding;
  final Value<String> calcBasis;
  final Value<String> interval;
  final Value<double?> minSpendThreshold;
  final Value<double?> minTxAmount;
  final Value<double?> capAmount;
  final Value<String?> capSharedKey;
  final Value<DateTime?> startsAt;
  final Value<DateTime?> endsAt;
  final Value<String> settlementType;
  final Value<int?> settlementDays;
  final Value<int?> settlementMonthOffset;
  final Value<int?> settlementDayOfMonth;
  final Value<int?> rewardAccountId;
  final Value<String?> note;
  final Value<bool> enabled;
  final Value<int> sortOrder;
  final Value<DateTime?> createdAt;
  final Value<DateTime?> updatedAt;
  const CardRewardRulesCompanion({
    this.id = const Value.absent(),
    this.accountId = const Value.absent(),
    this.syncId = const Value.absent(),
    this.label = const Value.absent(),
    this.categoryIdsJson = const Value.absent(),
    this.rateType = const Value.absent(),
    this.rateValue = const Value.absent(),
    this.rounding = const Value.absent(),
    this.totalRounding = const Value.absent(),
    this.calcBasis = const Value.absent(),
    this.interval = const Value.absent(),
    this.minSpendThreshold = const Value.absent(),
    this.minTxAmount = const Value.absent(),
    this.capAmount = const Value.absent(),
    this.capSharedKey = const Value.absent(),
    this.startsAt = const Value.absent(),
    this.endsAt = const Value.absent(),
    this.settlementType = const Value.absent(),
    this.settlementDays = const Value.absent(),
    this.settlementMonthOffset = const Value.absent(),
    this.settlementDayOfMonth = const Value.absent(),
    this.rewardAccountId = const Value.absent(),
    this.note = const Value.absent(),
    this.enabled = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  CardRewardRulesCompanion.insert({
    this.id = const Value.absent(),
    required int accountId,
    this.syncId = const Value.absent(),
    required String label,
    this.categoryIdsJson = const Value.absent(),
    this.rateType = const Value.absent(),
    required double rateValue,
    this.rounding = const Value.absent(),
    this.totalRounding = const Value.absent(),
    this.calcBasis = const Value.absent(),
    this.interval = const Value.absent(),
    this.minSpendThreshold = const Value.absent(),
    this.minTxAmount = const Value.absent(),
    this.capAmount = const Value.absent(),
    this.capSharedKey = const Value.absent(),
    this.startsAt = const Value.absent(),
    this.endsAt = const Value.absent(),
    this.settlementType = const Value.absent(),
    this.settlementDays = const Value.absent(),
    this.settlementMonthOffset = const Value.absent(),
    this.settlementDayOfMonth = const Value.absent(),
    this.rewardAccountId = const Value.absent(),
    this.note = const Value.absent(),
    this.enabled = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  })  : accountId = Value(accountId),
        label = Value(label),
        rateValue = Value(rateValue);
  static Insertable<CardRewardRule> custom({
    Expression<int>? id,
    Expression<int>? accountId,
    Expression<String>? syncId,
    Expression<String>? label,
    Expression<String>? categoryIdsJson,
    Expression<String>? rateType,
    Expression<double>? rateValue,
    Expression<String>? rounding,
    Expression<String>? totalRounding,
    Expression<String>? calcBasis,
    Expression<String>? interval,
    Expression<double>? minSpendThreshold,
    Expression<double>? minTxAmount,
    Expression<double>? capAmount,
    Expression<String>? capSharedKey,
    Expression<DateTime>? startsAt,
    Expression<DateTime>? endsAt,
    Expression<String>? settlementType,
    Expression<int>? settlementDays,
    Expression<int>? settlementMonthOffset,
    Expression<int>? settlementDayOfMonth,
    Expression<int>? rewardAccountId,
    Expression<String>? note,
    Expression<bool>? enabled,
    Expression<int>? sortOrder,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (accountId != null) 'account_id': accountId,
      if (syncId != null) 'sync_id': syncId,
      if (label != null) 'label': label,
      if (categoryIdsJson != null) 'category_ids_json': categoryIdsJson,
      if (rateType != null) 'rate_type': rateType,
      if (rateValue != null) 'rate_value': rateValue,
      if (rounding != null) 'rounding': rounding,
      if (totalRounding != null) 'total_rounding': totalRounding,
      if (calcBasis != null) 'calc_basis': calcBasis,
      if (interval != null) 'interval': interval,
      if (minSpendThreshold != null) 'min_spend_threshold': minSpendThreshold,
      if (minTxAmount != null) 'min_tx_amount': minTxAmount,
      if (capAmount != null) 'cap_amount': capAmount,
      if (capSharedKey != null) 'cap_shared_key': capSharedKey,
      if (startsAt != null) 'starts_at': startsAt,
      if (endsAt != null) 'ends_at': endsAt,
      if (settlementType != null) 'settlement_type': settlementType,
      if (settlementDays != null) 'settlement_days': settlementDays,
      if (settlementMonthOffset != null)
        'settlement_month_offset': settlementMonthOffset,
      if (settlementDayOfMonth != null)
        'settlement_day_of_month': settlementDayOfMonth,
      if (rewardAccountId != null) 'reward_account_id': rewardAccountId,
      if (note != null) 'note': note,
      if (enabled != null) 'enabled': enabled,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  CardRewardRulesCompanion copyWith(
      {Value<int>? id,
      Value<int>? accountId,
      Value<String?>? syncId,
      Value<String>? label,
      Value<String?>? categoryIdsJson,
      Value<String>? rateType,
      Value<double>? rateValue,
      Value<String>? rounding,
      Value<String>? totalRounding,
      Value<String>? calcBasis,
      Value<String>? interval,
      Value<double?>? minSpendThreshold,
      Value<double?>? minTxAmount,
      Value<double?>? capAmount,
      Value<String?>? capSharedKey,
      Value<DateTime?>? startsAt,
      Value<DateTime?>? endsAt,
      Value<String>? settlementType,
      Value<int?>? settlementDays,
      Value<int?>? settlementMonthOffset,
      Value<int?>? settlementDayOfMonth,
      Value<int?>? rewardAccountId,
      Value<String?>? note,
      Value<bool>? enabled,
      Value<int>? sortOrder,
      Value<DateTime?>? createdAt,
      Value<DateTime?>? updatedAt}) {
    return CardRewardRulesCompanion(
      id: id ?? this.id,
      accountId: accountId ?? this.accountId,
      syncId: syncId ?? this.syncId,
      label: label ?? this.label,
      categoryIdsJson: categoryIdsJson ?? this.categoryIdsJson,
      rateType: rateType ?? this.rateType,
      rateValue: rateValue ?? this.rateValue,
      rounding: rounding ?? this.rounding,
      totalRounding: totalRounding ?? this.totalRounding,
      calcBasis: calcBasis ?? this.calcBasis,
      interval: interval ?? this.interval,
      minSpendThreshold: minSpendThreshold ?? this.minSpendThreshold,
      minTxAmount: minTxAmount ?? this.minTxAmount,
      capAmount: capAmount ?? this.capAmount,
      capSharedKey: capSharedKey ?? this.capSharedKey,
      startsAt: startsAt ?? this.startsAt,
      endsAt: endsAt ?? this.endsAt,
      settlementType: settlementType ?? this.settlementType,
      settlementDays: settlementDays ?? this.settlementDays,
      settlementMonthOffset:
          settlementMonthOffset ?? this.settlementMonthOffset,
      settlementDayOfMonth: settlementDayOfMonth ?? this.settlementDayOfMonth,
      rewardAccountId: rewardAccountId ?? this.rewardAccountId,
      note: note ?? this.note,
      enabled: enabled ?? this.enabled,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (accountId.present) {
      map['account_id'] = Variable<int>(accountId.value);
    }
    if (syncId.present) {
      map['sync_id'] = Variable<String>(syncId.value);
    }
    if (label.present) {
      map['label'] = Variable<String>(label.value);
    }
    if (categoryIdsJson.present) {
      map['category_ids_json'] = Variable<String>(categoryIdsJson.value);
    }
    if (rateType.present) {
      map['rate_type'] = Variable<String>(rateType.value);
    }
    if (rateValue.present) {
      map['rate_value'] = Variable<double>(rateValue.value);
    }
    if (rounding.present) {
      map['rounding'] = Variable<String>(rounding.value);
    }
    if (totalRounding.present) {
      map['total_rounding'] = Variable<String>(totalRounding.value);
    }
    if (calcBasis.present) {
      map['calc_basis'] = Variable<String>(calcBasis.value);
    }
    if (interval.present) {
      map['interval'] = Variable<String>(interval.value);
    }
    if (minSpendThreshold.present) {
      map['min_spend_threshold'] = Variable<double>(minSpendThreshold.value);
    }
    if (minTxAmount.present) {
      map['min_tx_amount'] = Variable<double>(minTxAmount.value);
    }
    if (capAmount.present) {
      map['cap_amount'] = Variable<double>(capAmount.value);
    }
    if (capSharedKey.present) {
      map['cap_shared_key'] = Variable<String>(capSharedKey.value);
    }
    if (startsAt.present) {
      map['starts_at'] = Variable<DateTime>(startsAt.value);
    }
    if (endsAt.present) {
      map['ends_at'] = Variable<DateTime>(endsAt.value);
    }
    if (settlementType.present) {
      map['settlement_type'] = Variable<String>(settlementType.value);
    }
    if (settlementDays.present) {
      map['settlement_days'] = Variable<int>(settlementDays.value);
    }
    if (settlementMonthOffset.present) {
      map['settlement_month_offset'] =
          Variable<int>(settlementMonthOffset.value);
    }
    if (settlementDayOfMonth.present) {
      map['settlement_day_of_month'] =
          Variable<int>(settlementDayOfMonth.value);
    }
    if (rewardAccountId.present) {
      map['reward_account_id'] = Variable<int>(rewardAccountId.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CardRewardRulesCompanion(')
          ..write('id: $id, ')
          ..write('accountId: $accountId, ')
          ..write('syncId: $syncId, ')
          ..write('label: $label, ')
          ..write('categoryIdsJson: $categoryIdsJson, ')
          ..write('rateType: $rateType, ')
          ..write('rateValue: $rateValue, ')
          ..write('rounding: $rounding, ')
          ..write('totalRounding: $totalRounding, ')
          ..write('calcBasis: $calcBasis, ')
          ..write('interval: $interval, ')
          ..write('minSpendThreshold: $minSpendThreshold, ')
          ..write('minTxAmount: $minTxAmount, ')
          ..write('capAmount: $capAmount, ')
          ..write('capSharedKey: $capSharedKey, ')
          ..write('startsAt: $startsAt, ')
          ..write('endsAt: $endsAt, ')
          ..write('settlementType: $settlementType, ')
          ..write('settlementDays: $settlementDays, ')
          ..write('settlementMonthOffset: $settlementMonthOffset, ')
          ..write('settlementDayOfMonth: $settlementDayOfMonth, ')
          ..write('rewardAccountId: $rewardAccountId, ')
          ..write('note: $note, ')
          ..write('enabled: $enabled, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $TransactionSplitsTable extends TransactionSplits
    with TableInfo<$TransactionSplitsTable, TransactionSplit> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TransactionSplitsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _transactionIdMeta =
      const VerificationMeta('transactionId');
  @override
  late final GeneratedColumn<int> transactionId = GeneratedColumn<int>(
      'transaction_id', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _categoryIdMeta =
      const VerificationMeta('categoryId');
  @override
  late final GeneratedColumn<int> categoryId = GeneratedColumn<int>(
      'category_id', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _categorySyncIdOverrideMeta =
      const VerificationMeta('categorySyncIdOverride');
  @override
  late final GeneratedColumn<String> categorySyncIdOverride =
      GeneratedColumn<String>('category_sync_id_override', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _amountMeta = const VerificationMeta('amount');
  @override
  late final GeneratedColumn<double> amount = GeneratedColumn<double>(
      'amount', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
      'note', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _sortOrderMeta =
      const VerificationMeta('sortOrder');
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
      'sort_order', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  @override
  List<GeneratedColumn> get $columns => [
        id,
        transactionId,
        categoryId,
        categorySyncIdOverride,
        amount,
        note,
        sortOrder
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'transaction_splits';
  @override
  VerificationContext validateIntegrity(Insertable<TransactionSplit> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('transaction_id')) {
      context.handle(
          _transactionIdMeta,
          transactionId.isAcceptableOrUnknown(
              data['transaction_id']!, _transactionIdMeta));
    } else if (isInserting) {
      context.missing(_transactionIdMeta);
    }
    if (data.containsKey('category_id')) {
      context.handle(
          _categoryIdMeta,
          categoryId.isAcceptableOrUnknown(
              data['category_id']!, _categoryIdMeta));
    }
    if (data.containsKey('category_sync_id_override')) {
      context.handle(
          _categorySyncIdOverrideMeta,
          categorySyncIdOverride.isAcceptableOrUnknown(
              data['category_sync_id_override']!, _categorySyncIdOverrideMeta));
    }
    if (data.containsKey('amount')) {
      context.handle(_amountMeta,
          amount.isAcceptableOrUnknown(data['amount']!, _amountMeta));
    } else if (isInserting) {
      context.missing(_amountMeta);
    }
    if (data.containsKey('note')) {
      context.handle(
          _noteMeta, note.isAcceptableOrUnknown(data['note']!, _noteMeta));
    }
    if (data.containsKey('sort_order')) {
      context.handle(_sortOrderMeta,
          sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TransactionSplit map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TransactionSplit(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      transactionId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}transaction_id'])!,
      categoryId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}category_id']),
      categorySyncIdOverride: attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}category_sync_id_override']),
      amount: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}amount'])!,
      note: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}note']),
      sortOrder: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}sort_order'])!,
    );
  }

  @override
  $TransactionSplitsTable createAlias(String alias) {
    return $TransactionSplitsTable(attachedDatabase, alias);
  }
}

class TransactionSplit extends DataClass
    implements Insertable<TransactionSplit> {
  final int id;
  final int transactionId;
  final int? categoryId;
  final String? categorySyncIdOverride;
  final double amount;
  final String? note;
  final int sortOrder;
  const TransactionSplit(
      {required this.id,
      required this.transactionId,
      this.categoryId,
      this.categorySyncIdOverride,
      required this.amount,
      this.note,
      required this.sortOrder});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['transaction_id'] = Variable<int>(transactionId);
    if (!nullToAbsent || categoryId != null) {
      map['category_id'] = Variable<int>(categoryId);
    }
    if (!nullToAbsent || categorySyncIdOverride != null) {
      map['category_sync_id_override'] =
          Variable<String>(categorySyncIdOverride);
    }
    map['amount'] = Variable<double>(amount);
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    map['sort_order'] = Variable<int>(sortOrder);
    return map;
  }

  TransactionSplitsCompanion toCompanion(bool nullToAbsent) {
    return TransactionSplitsCompanion(
      id: Value(id),
      transactionId: Value(transactionId),
      categoryId: categoryId == null && nullToAbsent
          ? const Value.absent()
          : Value(categoryId),
      categorySyncIdOverride: categorySyncIdOverride == null && nullToAbsent
          ? const Value.absent()
          : Value(categorySyncIdOverride),
      amount: Value(amount),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      sortOrder: Value(sortOrder),
    );
  }

  factory TransactionSplit.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TransactionSplit(
      id: serializer.fromJson<int>(json['id']),
      transactionId: serializer.fromJson<int>(json['transactionId']),
      categoryId: serializer.fromJson<int?>(json['categoryId']),
      categorySyncIdOverride:
          serializer.fromJson<String?>(json['categorySyncIdOverride']),
      amount: serializer.fromJson<double>(json['amount']),
      note: serializer.fromJson<String?>(json['note']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'transactionId': serializer.toJson<int>(transactionId),
      'categoryId': serializer.toJson<int?>(categoryId),
      'categorySyncIdOverride':
          serializer.toJson<String?>(categorySyncIdOverride),
      'amount': serializer.toJson<double>(amount),
      'note': serializer.toJson<String?>(note),
      'sortOrder': serializer.toJson<int>(sortOrder),
    };
  }

  TransactionSplit copyWith(
          {int? id,
          int? transactionId,
          Value<int?> categoryId = const Value.absent(),
          Value<String?> categorySyncIdOverride = const Value.absent(),
          double? amount,
          Value<String?> note = const Value.absent(),
          int? sortOrder}) =>
      TransactionSplit(
        id: id ?? this.id,
        transactionId: transactionId ?? this.transactionId,
        categoryId: categoryId.present ? categoryId.value : this.categoryId,
        categorySyncIdOverride: categorySyncIdOverride.present
            ? categorySyncIdOverride.value
            : this.categorySyncIdOverride,
        amount: amount ?? this.amount,
        note: note.present ? note.value : this.note,
        sortOrder: sortOrder ?? this.sortOrder,
      );
  TransactionSplit copyWithCompanion(TransactionSplitsCompanion data) {
    return TransactionSplit(
      id: data.id.present ? data.id.value : this.id,
      transactionId: data.transactionId.present
          ? data.transactionId.value
          : this.transactionId,
      categoryId:
          data.categoryId.present ? data.categoryId.value : this.categoryId,
      categorySyncIdOverride: data.categorySyncIdOverride.present
          ? data.categorySyncIdOverride.value
          : this.categorySyncIdOverride,
      amount: data.amount.present ? data.amount.value : this.amount,
      note: data.note.present ? data.note.value : this.note,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TransactionSplit(')
          ..write('id: $id, ')
          ..write('transactionId: $transactionId, ')
          ..write('categoryId: $categoryId, ')
          ..write('categorySyncIdOverride: $categorySyncIdOverride, ')
          ..write('amount: $amount, ')
          ..write('note: $note, ')
          ..write('sortOrder: $sortOrder')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, transactionId, categoryId,
      categorySyncIdOverride, amount, note, sortOrder);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TransactionSplit &&
          other.id == this.id &&
          other.transactionId == this.transactionId &&
          other.categoryId == this.categoryId &&
          other.categorySyncIdOverride == this.categorySyncIdOverride &&
          other.amount == this.amount &&
          other.note == this.note &&
          other.sortOrder == this.sortOrder);
}

class TransactionSplitsCompanion extends UpdateCompanion<TransactionSplit> {
  final Value<int> id;
  final Value<int> transactionId;
  final Value<int?> categoryId;
  final Value<String?> categorySyncIdOverride;
  final Value<double> amount;
  final Value<String?> note;
  final Value<int> sortOrder;
  const TransactionSplitsCompanion({
    this.id = const Value.absent(),
    this.transactionId = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.categorySyncIdOverride = const Value.absent(),
    this.amount = const Value.absent(),
    this.note = const Value.absent(),
    this.sortOrder = const Value.absent(),
  });
  TransactionSplitsCompanion.insert({
    this.id = const Value.absent(),
    required int transactionId,
    this.categoryId = const Value.absent(),
    this.categorySyncIdOverride = const Value.absent(),
    required double amount,
    this.note = const Value.absent(),
    this.sortOrder = const Value.absent(),
  })  : transactionId = Value(transactionId),
        amount = Value(amount);
  static Insertable<TransactionSplit> custom({
    Expression<int>? id,
    Expression<int>? transactionId,
    Expression<int>? categoryId,
    Expression<String>? categorySyncIdOverride,
    Expression<double>? amount,
    Expression<String>? note,
    Expression<int>? sortOrder,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (transactionId != null) 'transaction_id': transactionId,
      if (categoryId != null) 'category_id': categoryId,
      if (categorySyncIdOverride != null)
        'category_sync_id_override': categorySyncIdOverride,
      if (amount != null) 'amount': amount,
      if (note != null) 'note': note,
      if (sortOrder != null) 'sort_order': sortOrder,
    });
  }

  TransactionSplitsCompanion copyWith(
      {Value<int>? id,
      Value<int>? transactionId,
      Value<int?>? categoryId,
      Value<String?>? categorySyncIdOverride,
      Value<double>? amount,
      Value<String?>? note,
      Value<int>? sortOrder}) {
    return TransactionSplitsCompanion(
      id: id ?? this.id,
      transactionId: transactionId ?? this.transactionId,
      categoryId: categoryId ?? this.categoryId,
      categorySyncIdOverride:
          categorySyncIdOverride ?? this.categorySyncIdOverride,
      amount: amount ?? this.amount,
      note: note ?? this.note,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (transactionId.present) {
      map['transaction_id'] = Variable<int>(transactionId.value);
    }
    if (categoryId.present) {
      map['category_id'] = Variable<int>(categoryId.value);
    }
    if (categorySyncIdOverride.present) {
      map['category_sync_id_override'] =
          Variable<String>(categorySyncIdOverride.value);
    }
    if (amount.present) {
      map['amount'] = Variable<double>(amount.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TransactionSplitsCompanion(')
          ..write('id: $id, ')
          ..write('transactionId: $transactionId, ')
          ..write('categoryId: $categoryId, ')
          ..write('categorySyncIdOverride: $categorySyncIdOverride, ')
          ..write('amount: $amount, ')
          ..write('note: $note, ')
          ..write('sortOrder: $sortOrder')
          ..write(')'))
        .toString();
  }
}

class $DebtsTable extends Debts with TableInfo<$DebtsTable, Debt> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DebtsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _syncIdMeta = const VerificationMeta('syncId');
  @override
  late final GeneratedColumn<String> syncId = GeneratedColumn<String>(
      'sync_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _ledgerIdMeta =
      const VerificationMeta('ledgerId');
  @override
  late final GeneratedColumn<int> ledgerId = GeneratedColumn<int>(
      'ledger_id', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _directionMeta =
      const VerificationMeta('direction');
  @override
  late final GeneratedColumn<String> direction = GeneratedColumn<String>(
      'direction', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _counterpartyNameMeta =
      const VerificationMeta('counterpartyName');
  @override
  late final GeneratedColumn<String> counterpartyName = GeneratedColumn<String>(
      'counterparty_name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _principalAmountMeta =
      const VerificationMeta('principalAmount');
  @override
  late final GeneratedColumn<double> principalAmount = GeneratedColumn<double>(
      'principal_amount', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _dueAtMeta = const VerificationMeta('dueAt');
  @override
  late final GeneratedColumn<DateTime> dueAt = GeneratedColumn<DateTime>(
      'due_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
      'note', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _closedAtMeta =
      const VerificationMeta('closedAt');
  @override
  late final GeneratedColumn<DateTime> closedAt = GeneratedColumn<DateTime>(
      'closed_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _categoryIdMeta =
      const VerificationMeta('categoryId');
  @override
  late final GeneratedColumn<int> categoryId = GeneratedColumn<int>(
      'category_id', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _originTransactionSyncIdMeta =
      const VerificationMeta('originTransactionSyncId');
  @override
  late final GeneratedColumn<String> originTransactionSyncId =
      GeneratedColumn<String>('origin_transaction_sync_id', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _excludedFromTotalMeta =
      const VerificationMeta('excludedFromTotal');
  @override
  late final GeneratedColumn<bool> excludedFromTotal = GeneratedColumn<bool>(
      'excluded_from_total', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("excluded_from_total" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        syncId,
        ledgerId,
        direction,
        counterpartyName,
        principalAmount,
        dueAt,
        note,
        closedAt,
        categoryId,
        originTransactionSyncId,
        excludedFromTotal,
        createdAt,
        updatedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'debts';
  @override
  VerificationContext validateIntegrity(Insertable<Debt> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('sync_id')) {
      context.handle(_syncIdMeta,
          syncId.isAcceptableOrUnknown(data['sync_id']!, _syncIdMeta));
    }
    if (data.containsKey('ledger_id')) {
      context.handle(_ledgerIdMeta,
          ledgerId.isAcceptableOrUnknown(data['ledger_id']!, _ledgerIdMeta));
    } else if (isInserting) {
      context.missing(_ledgerIdMeta);
    }
    if (data.containsKey('direction')) {
      context.handle(_directionMeta,
          direction.isAcceptableOrUnknown(data['direction']!, _directionMeta));
    } else if (isInserting) {
      context.missing(_directionMeta);
    }
    if (data.containsKey('counterparty_name')) {
      context.handle(
          _counterpartyNameMeta,
          counterpartyName.isAcceptableOrUnknown(
              data['counterparty_name']!, _counterpartyNameMeta));
    } else if (isInserting) {
      context.missing(_counterpartyNameMeta);
    }
    if (data.containsKey('principal_amount')) {
      context.handle(
          _principalAmountMeta,
          principalAmount.isAcceptableOrUnknown(
              data['principal_amount']!, _principalAmountMeta));
    } else if (isInserting) {
      context.missing(_principalAmountMeta);
    }
    if (data.containsKey('due_at')) {
      context.handle(
          _dueAtMeta, dueAt.isAcceptableOrUnknown(data['due_at']!, _dueAtMeta));
    }
    if (data.containsKey('note')) {
      context.handle(
          _noteMeta, note.isAcceptableOrUnknown(data['note']!, _noteMeta));
    }
    if (data.containsKey('closed_at')) {
      context.handle(_closedAtMeta,
          closedAt.isAcceptableOrUnknown(data['closed_at']!, _closedAtMeta));
    }
    if (data.containsKey('category_id')) {
      context.handle(
          _categoryIdMeta,
          categoryId.isAcceptableOrUnknown(
              data['category_id']!, _categoryIdMeta));
    }
    if (data.containsKey('origin_transaction_sync_id')) {
      context.handle(
          _originTransactionSyncIdMeta,
          originTransactionSyncId.isAcceptableOrUnknown(
              data['origin_transaction_sync_id']!,
              _originTransactionSyncIdMeta));
    }
    if (data.containsKey('excluded_from_total')) {
      context.handle(
          _excludedFromTotalMeta,
          excludedFromTotal.isAcceptableOrUnknown(
              data['excluded_from_total']!, _excludedFromTotalMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Debt map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Debt(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      syncId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}sync_id']),
      ledgerId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}ledger_id'])!,
      direction: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}direction'])!,
      counterpartyName: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}counterparty_name'])!,
      principalAmount: attachedDatabase.typeMapping.read(
          DriftSqlType.double, data['${effectivePrefix}principal_amount'])!,
      dueAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}due_at']),
      note: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}note']),
      closedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}closed_at']),
      categoryId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}category_id']),
      originTransactionSyncId: attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}origin_transaction_sync_id']),
      excludedFromTotal: attachedDatabase.typeMapping.read(
          DriftSqlType.bool, data['${effectivePrefix}excluded_from_total'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $DebtsTable createAlias(String alias) {
    return $DebtsTable(attachedDatabase, alias);
  }
}

class Debt extends DataClass implements Insertable<Debt> {
  final int id;

  /// 跨设备同步 syncId(UUID)。新建必须填(同 budget 的约定)。
  final String? syncId;

  /// 关联账本ID
  final int ledgerId;

  /// 'payable'(我欠款) / 'receivable'(別人欠我)。見
  /// [kDebtDirectionPayable]/[kDebtDirectionReceivable]。
  final String direction;

  /// 對象名稱(人名/機構名),對齐 Cloud counterpartyName。
  final String counterpartyName;

  /// 本金,建立後不可改。
  final double principalAmount;

  /// 到期日,只取日期語意(同 deferredPostingAt 的處理慣例:一律用 UTC
  /// 年月日當日期的權威表示,不做時區位移)。null = 沒有到期日。
  final DateTime? dueAt;
  final String? note;

  /// 非 null = 手動結案(見 [kDebtStatusClosed])。優先於金額判斷的狀態——
  /// 手動結案可以在未還清時發生(呆帳/不再追蹤)。
  final DateTime? closedAt;

  /// v41:分類(原始設計刻意留空,使用者反饋後補上)。跟 [Transactions.categoryId]
  /// 一樣不宣告 FK,零存在性驗證。
  final int? categoryId;

  /// v41:起點交易反查——建立欠款時 App 會同時寫一筆帳戶餘額起點交易,但那筆
  /// 交易刻意不帶 [Transactions.debtSyncId](避免被還款金額加總誤計入,見上方
  /// docstring),所以要存這個欄位才能反查回那筆交易。存 syncId 字串直連,
  /// 不解析成本地 id(那筆交易未必已經同步下來)。建立後不可改。
  final String? originTransactionSyncId;

  /// v42:排除計入總額(對齐 Moze「排除在帳戶總覽計算」)。只影響
  /// [DebtRepository.getNetDebtBalance]/[getDebtBalancesByLedgerForAllLedgers]
  /// 這兩個「總額」方法,不影響清單(getDebtsWithStatus/getAllDebts)或
  /// §5.5 通知中心的未結清清單——那兩者刻意不套用這個過濾。
  final bool excludedFromTotal;
  final DateTime createdAt;
  final DateTime updatedAt;
  const Debt(
      {required this.id,
      this.syncId,
      required this.ledgerId,
      required this.direction,
      required this.counterpartyName,
      required this.principalAmount,
      this.dueAt,
      this.note,
      this.closedAt,
      this.categoryId,
      this.originTransactionSyncId,
      required this.excludedFromTotal,
      required this.createdAt,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || syncId != null) {
      map['sync_id'] = Variable<String>(syncId);
    }
    map['ledger_id'] = Variable<int>(ledgerId);
    map['direction'] = Variable<String>(direction);
    map['counterparty_name'] = Variable<String>(counterpartyName);
    map['principal_amount'] = Variable<double>(principalAmount);
    if (!nullToAbsent || dueAt != null) {
      map['due_at'] = Variable<DateTime>(dueAt);
    }
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    if (!nullToAbsent || closedAt != null) {
      map['closed_at'] = Variable<DateTime>(closedAt);
    }
    if (!nullToAbsent || categoryId != null) {
      map['category_id'] = Variable<int>(categoryId);
    }
    if (!nullToAbsent || originTransactionSyncId != null) {
      map['origin_transaction_sync_id'] =
          Variable<String>(originTransactionSyncId);
    }
    map['excluded_from_total'] = Variable<bool>(excludedFromTotal);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  DebtsCompanion toCompanion(bool nullToAbsent) {
    return DebtsCompanion(
      id: Value(id),
      syncId:
          syncId == null && nullToAbsent ? const Value.absent() : Value(syncId),
      ledgerId: Value(ledgerId),
      direction: Value(direction),
      counterpartyName: Value(counterpartyName),
      principalAmount: Value(principalAmount),
      dueAt:
          dueAt == null && nullToAbsent ? const Value.absent() : Value(dueAt),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      closedAt: closedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(closedAt),
      categoryId: categoryId == null && nullToAbsent
          ? const Value.absent()
          : Value(categoryId),
      originTransactionSyncId: originTransactionSyncId == null && nullToAbsent
          ? const Value.absent()
          : Value(originTransactionSyncId),
      excludedFromTotal: Value(excludedFromTotal),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Debt.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Debt(
      id: serializer.fromJson<int>(json['id']),
      syncId: serializer.fromJson<String?>(json['syncId']),
      ledgerId: serializer.fromJson<int>(json['ledgerId']),
      direction: serializer.fromJson<String>(json['direction']),
      counterpartyName: serializer.fromJson<String>(json['counterpartyName']),
      principalAmount: serializer.fromJson<double>(json['principalAmount']),
      dueAt: serializer.fromJson<DateTime?>(json['dueAt']),
      note: serializer.fromJson<String?>(json['note']),
      closedAt: serializer.fromJson<DateTime?>(json['closedAt']),
      categoryId: serializer.fromJson<int?>(json['categoryId']),
      originTransactionSyncId:
          serializer.fromJson<String?>(json['originTransactionSyncId']),
      excludedFromTotal: serializer.fromJson<bool>(json['excludedFromTotal']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'syncId': serializer.toJson<String?>(syncId),
      'ledgerId': serializer.toJson<int>(ledgerId),
      'direction': serializer.toJson<String>(direction),
      'counterpartyName': serializer.toJson<String>(counterpartyName),
      'principalAmount': serializer.toJson<double>(principalAmount),
      'dueAt': serializer.toJson<DateTime?>(dueAt),
      'note': serializer.toJson<String?>(note),
      'closedAt': serializer.toJson<DateTime?>(closedAt),
      'categoryId': serializer.toJson<int?>(categoryId),
      'originTransactionSyncId':
          serializer.toJson<String?>(originTransactionSyncId),
      'excludedFromTotal': serializer.toJson<bool>(excludedFromTotal),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Debt copyWith(
          {int? id,
          Value<String?> syncId = const Value.absent(),
          int? ledgerId,
          String? direction,
          String? counterpartyName,
          double? principalAmount,
          Value<DateTime?> dueAt = const Value.absent(),
          Value<String?> note = const Value.absent(),
          Value<DateTime?> closedAt = const Value.absent(),
          Value<int?> categoryId = const Value.absent(),
          Value<String?> originTransactionSyncId = const Value.absent(),
          bool? excludedFromTotal,
          DateTime? createdAt,
          DateTime? updatedAt}) =>
      Debt(
        id: id ?? this.id,
        syncId: syncId.present ? syncId.value : this.syncId,
        ledgerId: ledgerId ?? this.ledgerId,
        direction: direction ?? this.direction,
        counterpartyName: counterpartyName ?? this.counterpartyName,
        principalAmount: principalAmount ?? this.principalAmount,
        dueAt: dueAt.present ? dueAt.value : this.dueAt,
        note: note.present ? note.value : this.note,
        closedAt: closedAt.present ? closedAt.value : this.closedAt,
        categoryId: categoryId.present ? categoryId.value : this.categoryId,
        originTransactionSyncId: originTransactionSyncId.present
            ? originTransactionSyncId.value
            : this.originTransactionSyncId,
        excludedFromTotal: excludedFromTotal ?? this.excludedFromTotal,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  Debt copyWithCompanion(DebtsCompanion data) {
    return Debt(
      id: data.id.present ? data.id.value : this.id,
      syncId: data.syncId.present ? data.syncId.value : this.syncId,
      ledgerId: data.ledgerId.present ? data.ledgerId.value : this.ledgerId,
      direction: data.direction.present ? data.direction.value : this.direction,
      counterpartyName: data.counterpartyName.present
          ? data.counterpartyName.value
          : this.counterpartyName,
      principalAmount: data.principalAmount.present
          ? data.principalAmount.value
          : this.principalAmount,
      dueAt: data.dueAt.present ? data.dueAt.value : this.dueAt,
      note: data.note.present ? data.note.value : this.note,
      closedAt: data.closedAt.present ? data.closedAt.value : this.closedAt,
      categoryId:
          data.categoryId.present ? data.categoryId.value : this.categoryId,
      originTransactionSyncId: data.originTransactionSyncId.present
          ? data.originTransactionSyncId.value
          : this.originTransactionSyncId,
      excludedFromTotal: data.excludedFromTotal.present
          ? data.excludedFromTotal.value
          : this.excludedFromTotal,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Debt(')
          ..write('id: $id, ')
          ..write('syncId: $syncId, ')
          ..write('ledgerId: $ledgerId, ')
          ..write('direction: $direction, ')
          ..write('counterpartyName: $counterpartyName, ')
          ..write('principalAmount: $principalAmount, ')
          ..write('dueAt: $dueAt, ')
          ..write('note: $note, ')
          ..write('closedAt: $closedAt, ')
          ..write('categoryId: $categoryId, ')
          ..write('originTransactionSyncId: $originTransactionSyncId, ')
          ..write('excludedFromTotal: $excludedFromTotal, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      syncId,
      ledgerId,
      direction,
      counterpartyName,
      principalAmount,
      dueAt,
      note,
      closedAt,
      categoryId,
      originTransactionSyncId,
      excludedFromTotal,
      createdAt,
      updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Debt &&
          other.id == this.id &&
          other.syncId == this.syncId &&
          other.ledgerId == this.ledgerId &&
          other.direction == this.direction &&
          other.counterpartyName == this.counterpartyName &&
          other.principalAmount == this.principalAmount &&
          other.dueAt == this.dueAt &&
          other.note == this.note &&
          other.closedAt == this.closedAt &&
          other.categoryId == this.categoryId &&
          other.originTransactionSyncId == this.originTransactionSyncId &&
          other.excludedFromTotal == this.excludedFromTotal &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class DebtsCompanion extends UpdateCompanion<Debt> {
  final Value<int> id;
  final Value<String?> syncId;
  final Value<int> ledgerId;
  final Value<String> direction;
  final Value<String> counterpartyName;
  final Value<double> principalAmount;
  final Value<DateTime?> dueAt;
  final Value<String?> note;
  final Value<DateTime?> closedAt;
  final Value<int?> categoryId;
  final Value<String?> originTransactionSyncId;
  final Value<bool> excludedFromTotal;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  const DebtsCompanion({
    this.id = const Value.absent(),
    this.syncId = const Value.absent(),
    this.ledgerId = const Value.absent(),
    this.direction = const Value.absent(),
    this.counterpartyName = const Value.absent(),
    this.principalAmount = const Value.absent(),
    this.dueAt = const Value.absent(),
    this.note = const Value.absent(),
    this.closedAt = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.originTransactionSyncId = const Value.absent(),
    this.excludedFromTotal = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  DebtsCompanion.insert({
    this.id = const Value.absent(),
    this.syncId = const Value.absent(),
    required int ledgerId,
    required String direction,
    required String counterpartyName,
    required double principalAmount,
    this.dueAt = const Value.absent(),
    this.note = const Value.absent(),
    this.closedAt = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.originTransactionSyncId = const Value.absent(),
    this.excludedFromTotal = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  })  : ledgerId = Value(ledgerId),
        direction = Value(direction),
        counterpartyName = Value(counterpartyName),
        principalAmount = Value(principalAmount);
  static Insertable<Debt> custom({
    Expression<int>? id,
    Expression<String>? syncId,
    Expression<int>? ledgerId,
    Expression<String>? direction,
    Expression<String>? counterpartyName,
    Expression<double>? principalAmount,
    Expression<DateTime>? dueAt,
    Expression<String>? note,
    Expression<DateTime>? closedAt,
    Expression<int>? categoryId,
    Expression<String>? originTransactionSyncId,
    Expression<bool>? excludedFromTotal,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (syncId != null) 'sync_id': syncId,
      if (ledgerId != null) 'ledger_id': ledgerId,
      if (direction != null) 'direction': direction,
      if (counterpartyName != null) 'counterparty_name': counterpartyName,
      if (principalAmount != null) 'principal_amount': principalAmount,
      if (dueAt != null) 'due_at': dueAt,
      if (note != null) 'note': note,
      if (closedAt != null) 'closed_at': closedAt,
      if (categoryId != null) 'category_id': categoryId,
      if (originTransactionSyncId != null)
        'origin_transaction_sync_id': originTransactionSyncId,
      if (excludedFromTotal != null) 'excluded_from_total': excludedFromTotal,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  DebtsCompanion copyWith(
      {Value<int>? id,
      Value<String?>? syncId,
      Value<int>? ledgerId,
      Value<String>? direction,
      Value<String>? counterpartyName,
      Value<double>? principalAmount,
      Value<DateTime?>? dueAt,
      Value<String?>? note,
      Value<DateTime?>? closedAt,
      Value<int?>? categoryId,
      Value<String?>? originTransactionSyncId,
      Value<bool>? excludedFromTotal,
      Value<DateTime>? createdAt,
      Value<DateTime>? updatedAt}) {
    return DebtsCompanion(
      id: id ?? this.id,
      syncId: syncId ?? this.syncId,
      ledgerId: ledgerId ?? this.ledgerId,
      direction: direction ?? this.direction,
      counterpartyName: counterpartyName ?? this.counterpartyName,
      principalAmount: principalAmount ?? this.principalAmount,
      dueAt: dueAt ?? this.dueAt,
      note: note ?? this.note,
      closedAt: closedAt ?? this.closedAt,
      categoryId: categoryId ?? this.categoryId,
      originTransactionSyncId:
          originTransactionSyncId ?? this.originTransactionSyncId,
      excludedFromTotal: excludedFromTotal ?? this.excludedFromTotal,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (syncId.present) {
      map['sync_id'] = Variable<String>(syncId.value);
    }
    if (ledgerId.present) {
      map['ledger_id'] = Variable<int>(ledgerId.value);
    }
    if (direction.present) {
      map['direction'] = Variable<String>(direction.value);
    }
    if (counterpartyName.present) {
      map['counterparty_name'] = Variable<String>(counterpartyName.value);
    }
    if (principalAmount.present) {
      map['principal_amount'] = Variable<double>(principalAmount.value);
    }
    if (dueAt.present) {
      map['due_at'] = Variable<DateTime>(dueAt.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (closedAt.present) {
      map['closed_at'] = Variable<DateTime>(closedAt.value);
    }
    if (categoryId.present) {
      map['category_id'] = Variable<int>(categoryId.value);
    }
    if (originTransactionSyncId.present) {
      map['origin_transaction_sync_id'] =
          Variable<String>(originTransactionSyncId.value);
    }
    if (excludedFromTotal.present) {
      map['excluded_from_total'] = Variable<bool>(excludedFromTotal.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DebtsCompanion(')
          ..write('id: $id, ')
          ..write('syncId: $syncId, ')
          ..write('ledgerId: $ledgerId, ')
          ..write('direction: $direction, ')
          ..write('counterpartyName: $counterpartyName, ')
          ..write('principalAmount: $principalAmount, ')
          ..write('dueAt: $dueAt, ')
          ..write('note: $note, ')
          ..write('closedAt: $closedAt, ')
          ..write('categoryId: $categoryId, ')
          ..write('originTransactionSyncId: $originTransactionSyncId, ')
          ..write('excludedFromTotal: $excludedFromTotal, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $ProjectsTable extends Projects with TableInfo<$ProjectsTable, Project> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProjectsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _syncIdMeta = const VerificationMeta('syncId');
  @override
  late final GeneratedColumn<String> syncId = GeneratedColumn<String>(
      'sync_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _ledgerIdMeta =
      const VerificationMeta('ledgerId');
  @override
  late final GeneratedColumn<int> ledgerId = GeneratedColumn<int>(
      'ledger_id', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _iconMeta = const VerificationMeta('icon');
  @override
  late final GeneratedColumn<String> icon = GeneratedColumn<String>(
      'icon', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _budgetAmountMeta =
      const VerificationMeta('budgetAmount');
  @override
  late final GeneratedColumn<double> budgetAmount = GeneratedColumn<double>(
      'budget_amount', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _periodTypeMeta =
      const VerificationMeta('periodType');
  @override
  late final GeneratedColumn<String> periodType = GeneratedColumn<String>(
      'period_type', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('monthly'));
  static const VerificationMeta _periodStartMeta =
      const VerificationMeta('periodStart');
  @override
  late final GeneratedColumn<DateTime> periodStart = GeneratedColumn<DateTime>(
      'period_start', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _periodEndMeta =
      const VerificationMeta('periodEnd');
  @override
  late final GeneratedColumn<DateTime> periodEnd = GeneratedColumn<DateTime>(
      'period_end', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _carryoverEnabledMeta =
      const VerificationMeta('carryoverEnabled');
  @override
  late final GeneratedColumn<bool> carryoverEnabled = GeneratedColumn<bool>(
      'carryover_enabled', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("carryover_enabled" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _visibleOnHomeMeta =
      const VerificationMeta('visibleOnHome');
  @override
  late final GeneratedColumn<bool> visibleOnHome = GeneratedColumn<bool>(
      'visible_on_home', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("visible_on_home" IN (0, 1))'),
      defaultValue: const Constant(true));
  static const VerificationMeta _enabledMeta =
      const VerificationMeta('enabled');
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
      'enabled', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("enabled" IN (0, 1))'),
      defaultValue: const Constant(true));
  static const VerificationMeta _sortOrderMeta =
      const VerificationMeta('sortOrder');
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
      'sort_order', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        syncId,
        ledgerId,
        name,
        icon,
        budgetAmount,
        periodType,
        periodStart,
        periodEnd,
        carryoverEnabled,
        visibleOnHome,
        enabled,
        sortOrder,
        createdAt,
        updatedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'projects';
  @override
  VerificationContext validateIntegrity(Insertable<Project> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('sync_id')) {
      context.handle(_syncIdMeta,
          syncId.isAcceptableOrUnknown(data['sync_id']!, _syncIdMeta));
    }
    if (data.containsKey('ledger_id')) {
      context.handle(_ledgerIdMeta,
          ledgerId.isAcceptableOrUnknown(data['ledger_id']!, _ledgerIdMeta));
    } else if (isInserting) {
      context.missing(_ledgerIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    }
    if (data.containsKey('icon')) {
      context.handle(
          _iconMeta, icon.isAcceptableOrUnknown(data['icon']!, _iconMeta));
    }
    if (data.containsKey('budget_amount')) {
      context.handle(
          _budgetAmountMeta,
          budgetAmount.isAcceptableOrUnknown(
              data['budget_amount']!, _budgetAmountMeta));
    }
    if (data.containsKey('period_type')) {
      context.handle(
          _periodTypeMeta,
          periodType.isAcceptableOrUnknown(
              data['period_type']!, _periodTypeMeta));
    }
    if (data.containsKey('period_start')) {
      context.handle(
          _periodStartMeta,
          periodStart.isAcceptableOrUnknown(
              data['period_start']!, _periodStartMeta));
    }
    if (data.containsKey('period_end')) {
      context.handle(_periodEndMeta,
          periodEnd.isAcceptableOrUnknown(data['period_end']!, _periodEndMeta));
    }
    if (data.containsKey('carryover_enabled')) {
      context.handle(
          _carryoverEnabledMeta,
          carryoverEnabled.isAcceptableOrUnknown(
              data['carryover_enabled']!, _carryoverEnabledMeta));
    }
    if (data.containsKey('visible_on_home')) {
      context.handle(
          _visibleOnHomeMeta,
          visibleOnHome.isAcceptableOrUnknown(
              data['visible_on_home']!, _visibleOnHomeMeta));
    }
    if (data.containsKey('enabled')) {
      context.handle(_enabledMeta,
          enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta));
    }
    if (data.containsKey('sort_order')) {
      context.handle(_sortOrderMeta,
          sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Project map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Project(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      syncId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}sync_id']),
      ledgerId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}ledger_id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      icon: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}icon']),
      budgetAmount: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}budget_amount']),
      periodType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}period_type'])!,
      periodStart: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}period_start']),
      periodEnd: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}period_end']),
      carryoverEnabled: attachedDatabase.typeMapping.read(
          DriftSqlType.bool, data['${effectivePrefix}carryover_enabled'])!,
      visibleOnHome: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}visible_on_home'])!,
      enabled: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}enabled'])!,
      sortOrder: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}sort_order'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $ProjectsTable createAlias(String alias) {
    return $ProjectsTable(attachedDatabase, alias);
  }
}

class Project extends DataClass implements Insertable<Project> {
  final int id;

  /// 跨设备同步 syncId(UUID)。新建必须填(同 budget/debt 的约定)。
  final String? syncId;

  /// 关联账本ID
  final int ledgerId;
  final String name;

  /// emoji icon,可留空。
  final String? icon;

  /// 預算金額,null = 純記錄型(不設預算上限)。
  final double? budgetAmount;

  /// 週期類型:'monthly' / 'yearly' / 'fixed'。
  final String periodType;

  /// 起訖日,僅 periodType='fixed' 使用。
  final DateTime? periodStart;
  final DateTime? periodEnd;

  /// 結轉(僅 monthly/yearly 有意義,fixed 週期忽略)。
  final bool carryoverEnabled;

  /// 顯示於首頁。
  final bool visibleOnHome;

  /// 啟用/封存旗標(軟刪除)。刪除規則:有交易關聯 → 設 false(封存);沒有
  /// → 直接刪除整列。見 [ProjectRepository.deleteProject]。
  final bool enabled;

  /// 使用者自訂排序。
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;
  const Project(
      {required this.id,
      this.syncId,
      required this.ledgerId,
      required this.name,
      this.icon,
      this.budgetAmount,
      required this.periodType,
      this.periodStart,
      this.periodEnd,
      required this.carryoverEnabled,
      required this.visibleOnHome,
      required this.enabled,
      required this.sortOrder,
      required this.createdAt,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || syncId != null) {
      map['sync_id'] = Variable<String>(syncId);
    }
    map['ledger_id'] = Variable<int>(ledgerId);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || icon != null) {
      map['icon'] = Variable<String>(icon);
    }
    if (!nullToAbsent || budgetAmount != null) {
      map['budget_amount'] = Variable<double>(budgetAmount);
    }
    map['period_type'] = Variable<String>(periodType);
    if (!nullToAbsent || periodStart != null) {
      map['period_start'] = Variable<DateTime>(periodStart);
    }
    if (!nullToAbsent || periodEnd != null) {
      map['period_end'] = Variable<DateTime>(periodEnd);
    }
    map['carryover_enabled'] = Variable<bool>(carryoverEnabled);
    map['visible_on_home'] = Variable<bool>(visibleOnHome);
    map['enabled'] = Variable<bool>(enabled);
    map['sort_order'] = Variable<int>(sortOrder);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ProjectsCompanion toCompanion(bool nullToAbsent) {
    return ProjectsCompanion(
      id: Value(id),
      syncId:
          syncId == null && nullToAbsent ? const Value.absent() : Value(syncId),
      ledgerId: Value(ledgerId),
      name: Value(name),
      icon: icon == null && nullToAbsent ? const Value.absent() : Value(icon),
      budgetAmount: budgetAmount == null && nullToAbsent
          ? const Value.absent()
          : Value(budgetAmount),
      periodType: Value(periodType),
      periodStart: periodStart == null && nullToAbsent
          ? const Value.absent()
          : Value(periodStart),
      periodEnd: periodEnd == null && nullToAbsent
          ? const Value.absent()
          : Value(periodEnd),
      carryoverEnabled: Value(carryoverEnabled),
      visibleOnHome: Value(visibleOnHome),
      enabled: Value(enabled),
      sortOrder: Value(sortOrder),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Project.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Project(
      id: serializer.fromJson<int>(json['id']),
      syncId: serializer.fromJson<String?>(json['syncId']),
      ledgerId: serializer.fromJson<int>(json['ledgerId']),
      name: serializer.fromJson<String>(json['name']),
      icon: serializer.fromJson<String?>(json['icon']),
      budgetAmount: serializer.fromJson<double?>(json['budgetAmount']),
      periodType: serializer.fromJson<String>(json['periodType']),
      periodStart: serializer.fromJson<DateTime?>(json['periodStart']),
      periodEnd: serializer.fromJson<DateTime?>(json['periodEnd']),
      carryoverEnabled: serializer.fromJson<bool>(json['carryoverEnabled']),
      visibleOnHome: serializer.fromJson<bool>(json['visibleOnHome']),
      enabled: serializer.fromJson<bool>(json['enabled']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'syncId': serializer.toJson<String?>(syncId),
      'ledgerId': serializer.toJson<int>(ledgerId),
      'name': serializer.toJson<String>(name),
      'icon': serializer.toJson<String?>(icon),
      'budgetAmount': serializer.toJson<double?>(budgetAmount),
      'periodType': serializer.toJson<String>(periodType),
      'periodStart': serializer.toJson<DateTime?>(periodStart),
      'periodEnd': serializer.toJson<DateTime?>(periodEnd),
      'carryoverEnabled': serializer.toJson<bool>(carryoverEnabled),
      'visibleOnHome': serializer.toJson<bool>(visibleOnHome),
      'enabled': serializer.toJson<bool>(enabled),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Project copyWith(
          {int? id,
          Value<String?> syncId = const Value.absent(),
          int? ledgerId,
          String? name,
          Value<String?> icon = const Value.absent(),
          Value<double?> budgetAmount = const Value.absent(),
          String? periodType,
          Value<DateTime?> periodStart = const Value.absent(),
          Value<DateTime?> periodEnd = const Value.absent(),
          bool? carryoverEnabled,
          bool? visibleOnHome,
          bool? enabled,
          int? sortOrder,
          DateTime? createdAt,
          DateTime? updatedAt}) =>
      Project(
        id: id ?? this.id,
        syncId: syncId.present ? syncId.value : this.syncId,
        ledgerId: ledgerId ?? this.ledgerId,
        name: name ?? this.name,
        icon: icon.present ? icon.value : this.icon,
        budgetAmount:
            budgetAmount.present ? budgetAmount.value : this.budgetAmount,
        periodType: periodType ?? this.periodType,
        periodStart: periodStart.present ? periodStart.value : this.periodStart,
        periodEnd: periodEnd.present ? periodEnd.value : this.periodEnd,
        carryoverEnabled: carryoverEnabled ?? this.carryoverEnabled,
        visibleOnHome: visibleOnHome ?? this.visibleOnHome,
        enabled: enabled ?? this.enabled,
        sortOrder: sortOrder ?? this.sortOrder,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  Project copyWithCompanion(ProjectsCompanion data) {
    return Project(
      id: data.id.present ? data.id.value : this.id,
      syncId: data.syncId.present ? data.syncId.value : this.syncId,
      ledgerId: data.ledgerId.present ? data.ledgerId.value : this.ledgerId,
      name: data.name.present ? data.name.value : this.name,
      icon: data.icon.present ? data.icon.value : this.icon,
      budgetAmount: data.budgetAmount.present
          ? data.budgetAmount.value
          : this.budgetAmount,
      periodType:
          data.periodType.present ? data.periodType.value : this.periodType,
      periodStart:
          data.periodStart.present ? data.periodStart.value : this.periodStart,
      periodEnd: data.periodEnd.present ? data.periodEnd.value : this.periodEnd,
      carryoverEnabled: data.carryoverEnabled.present
          ? data.carryoverEnabled.value
          : this.carryoverEnabled,
      visibleOnHome: data.visibleOnHome.present
          ? data.visibleOnHome.value
          : this.visibleOnHome,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Project(')
          ..write('id: $id, ')
          ..write('syncId: $syncId, ')
          ..write('ledgerId: $ledgerId, ')
          ..write('name: $name, ')
          ..write('icon: $icon, ')
          ..write('budgetAmount: $budgetAmount, ')
          ..write('periodType: $periodType, ')
          ..write('periodStart: $periodStart, ')
          ..write('periodEnd: $periodEnd, ')
          ..write('carryoverEnabled: $carryoverEnabled, ')
          ..write('visibleOnHome: $visibleOnHome, ')
          ..write('enabled: $enabled, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      syncId,
      ledgerId,
      name,
      icon,
      budgetAmount,
      periodType,
      periodStart,
      periodEnd,
      carryoverEnabled,
      visibleOnHome,
      enabled,
      sortOrder,
      createdAt,
      updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Project &&
          other.id == this.id &&
          other.syncId == this.syncId &&
          other.ledgerId == this.ledgerId &&
          other.name == this.name &&
          other.icon == this.icon &&
          other.budgetAmount == this.budgetAmount &&
          other.periodType == this.periodType &&
          other.periodStart == this.periodStart &&
          other.periodEnd == this.periodEnd &&
          other.carryoverEnabled == this.carryoverEnabled &&
          other.visibleOnHome == this.visibleOnHome &&
          other.enabled == this.enabled &&
          other.sortOrder == this.sortOrder &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class ProjectsCompanion extends UpdateCompanion<Project> {
  final Value<int> id;
  final Value<String?> syncId;
  final Value<int> ledgerId;
  final Value<String> name;
  final Value<String?> icon;
  final Value<double?> budgetAmount;
  final Value<String> periodType;
  final Value<DateTime?> periodStart;
  final Value<DateTime?> periodEnd;
  final Value<bool> carryoverEnabled;
  final Value<bool> visibleOnHome;
  final Value<bool> enabled;
  final Value<int> sortOrder;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  const ProjectsCompanion({
    this.id = const Value.absent(),
    this.syncId = const Value.absent(),
    this.ledgerId = const Value.absent(),
    this.name = const Value.absent(),
    this.icon = const Value.absent(),
    this.budgetAmount = const Value.absent(),
    this.periodType = const Value.absent(),
    this.periodStart = const Value.absent(),
    this.periodEnd = const Value.absent(),
    this.carryoverEnabled = const Value.absent(),
    this.visibleOnHome = const Value.absent(),
    this.enabled = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  ProjectsCompanion.insert({
    this.id = const Value.absent(),
    this.syncId = const Value.absent(),
    required int ledgerId,
    this.name = const Value.absent(),
    this.icon = const Value.absent(),
    this.budgetAmount = const Value.absent(),
    this.periodType = const Value.absent(),
    this.periodStart = const Value.absent(),
    this.periodEnd = const Value.absent(),
    this.carryoverEnabled = const Value.absent(),
    this.visibleOnHome = const Value.absent(),
    this.enabled = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  }) : ledgerId = Value(ledgerId);
  static Insertable<Project> custom({
    Expression<int>? id,
    Expression<String>? syncId,
    Expression<int>? ledgerId,
    Expression<String>? name,
    Expression<String>? icon,
    Expression<double>? budgetAmount,
    Expression<String>? periodType,
    Expression<DateTime>? periodStart,
    Expression<DateTime>? periodEnd,
    Expression<bool>? carryoverEnabled,
    Expression<bool>? visibleOnHome,
    Expression<bool>? enabled,
    Expression<int>? sortOrder,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (syncId != null) 'sync_id': syncId,
      if (ledgerId != null) 'ledger_id': ledgerId,
      if (name != null) 'name': name,
      if (icon != null) 'icon': icon,
      if (budgetAmount != null) 'budget_amount': budgetAmount,
      if (periodType != null) 'period_type': periodType,
      if (periodStart != null) 'period_start': periodStart,
      if (periodEnd != null) 'period_end': periodEnd,
      if (carryoverEnabled != null) 'carryover_enabled': carryoverEnabled,
      if (visibleOnHome != null) 'visible_on_home': visibleOnHome,
      if (enabled != null) 'enabled': enabled,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  ProjectsCompanion copyWith(
      {Value<int>? id,
      Value<String?>? syncId,
      Value<int>? ledgerId,
      Value<String>? name,
      Value<String?>? icon,
      Value<double?>? budgetAmount,
      Value<String>? periodType,
      Value<DateTime?>? periodStart,
      Value<DateTime?>? periodEnd,
      Value<bool>? carryoverEnabled,
      Value<bool>? visibleOnHome,
      Value<bool>? enabled,
      Value<int>? sortOrder,
      Value<DateTime>? createdAt,
      Value<DateTime>? updatedAt}) {
    return ProjectsCompanion(
      id: id ?? this.id,
      syncId: syncId ?? this.syncId,
      ledgerId: ledgerId ?? this.ledgerId,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      budgetAmount: budgetAmount ?? this.budgetAmount,
      periodType: periodType ?? this.periodType,
      periodStart: periodStart ?? this.periodStart,
      periodEnd: periodEnd ?? this.periodEnd,
      carryoverEnabled: carryoverEnabled ?? this.carryoverEnabled,
      visibleOnHome: visibleOnHome ?? this.visibleOnHome,
      enabled: enabled ?? this.enabled,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (syncId.present) {
      map['sync_id'] = Variable<String>(syncId.value);
    }
    if (ledgerId.present) {
      map['ledger_id'] = Variable<int>(ledgerId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (icon.present) {
      map['icon'] = Variable<String>(icon.value);
    }
    if (budgetAmount.present) {
      map['budget_amount'] = Variable<double>(budgetAmount.value);
    }
    if (periodType.present) {
      map['period_type'] = Variable<String>(periodType.value);
    }
    if (periodStart.present) {
      map['period_start'] = Variable<DateTime>(periodStart.value);
    }
    if (periodEnd.present) {
      map['period_end'] = Variable<DateTime>(periodEnd.value);
    }
    if (carryoverEnabled.present) {
      map['carryover_enabled'] = Variable<bool>(carryoverEnabled.value);
    }
    if (visibleOnHome.present) {
      map['visible_on_home'] = Variable<bool>(visibleOnHome.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProjectsCompanion(')
          ..write('id: $id, ')
          ..write('syncId: $syncId, ')
          ..write('ledgerId: $ledgerId, ')
          ..write('name: $name, ')
          ..write('icon: $icon, ')
          ..write('budgetAmount: $budgetAmount, ')
          ..write('periodType: $periodType, ')
          ..write('periodStart: $periodStart, ')
          ..write('periodEnd: $periodEnd, ')
          ..write('carryoverEnabled: $carryoverEnabled, ')
          ..write('visibleOnHome: $visibleOnHome, ')
          ..write('enabled: $enabled, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

abstract class _$BeeDatabase extends GeneratedDatabase {
  _$BeeDatabase(QueryExecutor e) : super(e);
  $BeeDatabaseManager get managers => $BeeDatabaseManager(this);
  late final $LedgersTable ledgers = $LedgersTable(this);
  late final $AccountsTable accounts = $AccountsTable(this);
  late final $CategoriesTable categories = $CategoriesTable(this);
  late final $TransactionsTable transactions = $TransactionsTable(this);
  late final $RecurringTransactionsTable recurringTransactions =
      $RecurringTransactionsTable(this);
  late final $ConversationsTable conversations = $ConversationsTable(this);
  late final $MessagesTable messages = $MessagesTable(this);
  late final $TagsTable tags = $TagsTable(this);
  late final $TransactionTagsTable transactionTags =
      $TransactionTagsTable(this);
  late final $BudgetsTable budgets = $BudgetsTable(this);
  late final $TransactionAttachmentsTable transactionAttachments =
      $TransactionAttachmentsTable(this);
  late final $LocalChangesTable localChanges = $LocalChangesTable(this);
  late final $SyncStateTable syncState = $SyncStateTable(this);
  late final $LedgerMembersTable ledgerMembers = $LedgerMembersTable(this);
  late final $SharedLedgerCategoriesTable sharedLedgerCategories =
      $SharedLedgerCategoriesTable(this);
  late final $SharedLedgerAccountsTable sharedLedgerAccounts =
      $SharedLedgerAccountsTable(this);
  late final $SharedLedgerTagsTable sharedLedgerTags =
      $SharedLedgerTagsTable(this);
  late final $TransactionTagOverridesTable transactionTagOverrides =
      $TransactionTagOverridesTable(this);
  late final $SyncPullErrorsTable syncPullErrors = $SyncPullErrorsTable(this);
  late final $ExchangeRatesTable exchangeRates = $ExchangeRatesTable(this);
  late final $ExchangeRateOverridesTable exchangeRateOverrides =
      $ExchangeRateOverridesTable(this);
  late final $CardRewardRulesTable cardRewardRules =
      $CardRewardRulesTable(this);
  late final $TransactionSplitsTable transactionSplits =
      $TransactionSplitsTable(this);
  late final $DebtsTable debts = $DebtsTable(this);
  late final $ProjectsTable projects = $ProjectsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
        ledgers,
        accounts,
        categories,
        transactions,
        recurringTransactions,
        conversations,
        messages,
        tags,
        transactionTags,
        budgets,
        transactionAttachments,
        localChanges,
        syncState,
        ledgerMembers,
        sharedLedgerCategories,
        sharedLedgerAccounts,
        sharedLedgerTags,
        transactionTagOverrides,
        syncPullErrors,
        exchangeRates,
        exchangeRateOverrides,
        cardRewardRules,
        transactionSplits,
        debts,
        projects
      ];
}

typedef $$LedgersTableCreateCompanionBuilder = LedgersCompanion Function({
  Value<int> id,
  required String name,
  Value<String> currency,
  Value<String> type,
  Value<DateTime> createdAt,
  Value<String?> syncId,
  Value<String> myRole,
  Value<int> memberCount,
  Value<bool> isShared,
  Value<String?> ownerUserId,
  Value<int> monthStartDay,
});
typedef $$LedgersTableUpdateCompanionBuilder = LedgersCompanion Function({
  Value<int> id,
  Value<String> name,
  Value<String> currency,
  Value<String> type,
  Value<DateTime> createdAt,
  Value<String?> syncId,
  Value<String> myRole,
  Value<int> memberCount,
  Value<bool> isShared,
  Value<String?> ownerUserId,
  Value<int> monthStartDay,
});

class $$LedgersTableFilterComposer
    extends Composer<_$BeeDatabase, $LedgersTable> {
  $$LedgersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get currency => $composableBuilder(
      column: $table.currency, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get syncId => $composableBuilder(
      column: $table.syncId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get myRole => $composableBuilder(
      column: $table.myRole, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get memberCount => $composableBuilder(
      column: $table.memberCount, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isShared => $composableBuilder(
      column: $table.isShared, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get ownerUserId => $composableBuilder(
      column: $table.ownerUserId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get monthStartDay => $composableBuilder(
      column: $table.monthStartDay, builder: (column) => ColumnFilters(column));
}

class $$LedgersTableOrderingComposer
    extends Composer<_$BeeDatabase, $LedgersTable> {
  $$LedgersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get currency => $composableBuilder(
      column: $table.currency, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get syncId => $composableBuilder(
      column: $table.syncId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get myRole => $composableBuilder(
      column: $table.myRole, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get memberCount => $composableBuilder(
      column: $table.memberCount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isShared => $composableBuilder(
      column: $table.isShared, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get ownerUserId => $composableBuilder(
      column: $table.ownerUserId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get monthStartDay => $composableBuilder(
      column: $table.monthStartDay,
      builder: (column) => ColumnOrderings(column));
}

class $$LedgersTableAnnotationComposer
    extends Composer<_$BeeDatabase, $LedgersTable> {
  $$LedgersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get currency =>
      $composableBuilder(column: $table.currency, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get syncId =>
      $composableBuilder(column: $table.syncId, builder: (column) => column);

  GeneratedColumn<String> get myRole =>
      $composableBuilder(column: $table.myRole, builder: (column) => column);

  GeneratedColumn<int> get memberCount => $composableBuilder(
      column: $table.memberCount, builder: (column) => column);

  GeneratedColumn<bool> get isShared =>
      $composableBuilder(column: $table.isShared, builder: (column) => column);

  GeneratedColumn<String> get ownerUserId => $composableBuilder(
      column: $table.ownerUserId, builder: (column) => column);

  GeneratedColumn<int> get monthStartDay => $composableBuilder(
      column: $table.monthStartDay, builder: (column) => column);
}

class $$LedgersTableTableManager extends RootTableManager<
    _$BeeDatabase,
    $LedgersTable,
    Ledger,
    $$LedgersTableFilterComposer,
    $$LedgersTableOrderingComposer,
    $$LedgersTableAnnotationComposer,
    $$LedgersTableCreateCompanionBuilder,
    $$LedgersTableUpdateCompanionBuilder,
    (Ledger, BaseReferences<_$BeeDatabase, $LedgersTable, Ledger>),
    Ledger,
    PrefetchHooks Function()> {
  $$LedgersTableTableManager(_$BeeDatabase db, $LedgersTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LedgersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LedgersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LedgersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String> currency = const Value.absent(),
            Value<String> type = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<String?> syncId = const Value.absent(),
            Value<String> myRole = const Value.absent(),
            Value<int> memberCount = const Value.absent(),
            Value<bool> isShared = const Value.absent(),
            Value<String?> ownerUserId = const Value.absent(),
            Value<int> monthStartDay = const Value.absent(),
          }) =>
              LedgersCompanion(
            id: id,
            name: name,
            currency: currency,
            type: type,
            createdAt: createdAt,
            syncId: syncId,
            myRole: myRole,
            memberCount: memberCount,
            isShared: isShared,
            ownerUserId: ownerUserId,
            monthStartDay: monthStartDay,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String name,
            Value<String> currency = const Value.absent(),
            Value<String> type = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<String?> syncId = const Value.absent(),
            Value<String> myRole = const Value.absent(),
            Value<int> memberCount = const Value.absent(),
            Value<bool> isShared = const Value.absent(),
            Value<String?> ownerUserId = const Value.absent(),
            Value<int> monthStartDay = const Value.absent(),
          }) =>
              LedgersCompanion.insert(
            id: id,
            name: name,
            currency: currency,
            type: type,
            createdAt: createdAt,
            syncId: syncId,
            myRole: myRole,
            memberCount: memberCount,
            isShared: isShared,
            ownerUserId: ownerUserId,
            monthStartDay: monthStartDay,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$LedgersTableProcessedTableManager = ProcessedTableManager<
    _$BeeDatabase,
    $LedgersTable,
    Ledger,
    $$LedgersTableFilterComposer,
    $$LedgersTableOrderingComposer,
    $$LedgersTableAnnotationComposer,
    $$LedgersTableCreateCompanionBuilder,
    $$LedgersTableUpdateCompanionBuilder,
    (Ledger, BaseReferences<_$BeeDatabase, $LedgersTable, Ledger>),
    Ledger,
    PrefetchHooks Function()>;
typedef $$AccountsTableCreateCompanionBuilder = AccountsCompanion Function({
  Value<int> id,
  required int ledgerId,
  required String name,
  Value<String> type,
  Value<String> currency,
  Value<double> initialBalance,
  Value<DateTime?> createdAt,
  Value<DateTime?> updatedAt,
  Value<int> sortOrder,
  Value<double?> creditLimit,
  Value<int?> billingDay,
  Value<int?> paymentDueDay,
  Value<String?> bankName,
  Value<String?> cardLastFour,
  Value<String?> note,
  Value<String?> syncId,
  Value<bool> hidden,
  Value<String?> parentAccountId,
  Value<String?> swipesmartCardId,
  Value<String?> avatarPath,
  Value<bool> includeInTotal,
});
typedef $$AccountsTableUpdateCompanionBuilder = AccountsCompanion Function({
  Value<int> id,
  Value<int> ledgerId,
  Value<String> name,
  Value<String> type,
  Value<String> currency,
  Value<double> initialBalance,
  Value<DateTime?> createdAt,
  Value<DateTime?> updatedAt,
  Value<int> sortOrder,
  Value<double?> creditLimit,
  Value<int?> billingDay,
  Value<int?> paymentDueDay,
  Value<String?> bankName,
  Value<String?> cardLastFour,
  Value<String?> note,
  Value<String?> syncId,
  Value<bool> hidden,
  Value<String?> parentAccountId,
  Value<String?> swipesmartCardId,
  Value<String?> avatarPath,
  Value<bool> includeInTotal,
});

class $$AccountsTableFilterComposer
    extends Composer<_$BeeDatabase, $AccountsTable> {
  $$AccountsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get ledgerId => $composableBuilder(
      column: $table.ledgerId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get currency => $composableBuilder(
      column: $table.currency, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get initialBalance => $composableBuilder(
      column: $table.initialBalance,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get sortOrder => $composableBuilder(
      column: $table.sortOrder, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get creditLimit => $composableBuilder(
      column: $table.creditLimit, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get billingDay => $composableBuilder(
      column: $table.billingDay, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get paymentDueDay => $composableBuilder(
      column: $table.paymentDueDay, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get bankName => $composableBuilder(
      column: $table.bankName, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get cardLastFour => $composableBuilder(
      column: $table.cardLastFour, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get note => $composableBuilder(
      column: $table.note, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get syncId => $composableBuilder(
      column: $table.syncId, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get hidden => $composableBuilder(
      column: $table.hidden, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get parentAccountId => $composableBuilder(
      column: $table.parentAccountId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get swipesmartCardId => $composableBuilder(
      column: $table.swipesmartCardId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get avatarPath => $composableBuilder(
      column: $table.avatarPath, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get includeInTotal => $composableBuilder(
      column: $table.includeInTotal,
      builder: (column) => ColumnFilters(column));
}

class $$AccountsTableOrderingComposer
    extends Composer<_$BeeDatabase, $AccountsTable> {
  $$AccountsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get ledgerId => $composableBuilder(
      column: $table.ledgerId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get currency => $composableBuilder(
      column: $table.currency, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get initialBalance => $composableBuilder(
      column: $table.initialBalance,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get sortOrder => $composableBuilder(
      column: $table.sortOrder, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get creditLimit => $composableBuilder(
      column: $table.creditLimit, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get billingDay => $composableBuilder(
      column: $table.billingDay, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get paymentDueDay => $composableBuilder(
      column: $table.paymentDueDay,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get bankName => $composableBuilder(
      column: $table.bankName, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get cardLastFour => $composableBuilder(
      column: $table.cardLastFour,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get note => $composableBuilder(
      column: $table.note, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get syncId => $composableBuilder(
      column: $table.syncId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get hidden => $composableBuilder(
      column: $table.hidden, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get parentAccountId => $composableBuilder(
      column: $table.parentAccountId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get swipesmartCardId => $composableBuilder(
      column: $table.swipesmartCardId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get avatarPath => $composableBuilder(
      column: $table.avatarPath, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get includeInTotal => $composableBuilder(
      column: $table.includeInTotal,
      builder: (column) => ColumnOrderings(column));
}

class $$AccountsTableAnnotationComposer
    extends Composer<_$BeeDatabase, $AccountsTable> {
  $$AccountsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get ledgerId =>
      $composableBuilder(column: $table.ledgerId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get currency =>
      $composableBuilder(column: $table.currency, builder: (column) => column);

  GeneratedColumn<double> get initialBalance => $composableBuilder(
      column: $table.initialBalance, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<double> get creditLimit => $composableBuilder(
      column: $table.creditLimit, builder: (column) => column);

  GeneratedColumn<int> get billingDay => $composableBuilder(
      column: $table.billingDay, builder: (column) => column);

  GeneratedColumn<int> get paymentDueDay => $composableBuilder(
      column: $table.paymentDueDay, builder: (column) => column);

  GeneratedColumn<String> get bankName =>
      $composableBuilder(column: $table.bankName, builder: (column) => column);

  GeneratedColumn<String> get cardLastFour => $composableBuilder(
      column: $table.cardLastFour, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<String> get syncId =>
      $composableBuilder(column: $table.syncId, builder: (column) => column);

  GeneratedColumn<bool> get hidden =>
      $composableBuilder(column: $table.hidden, builder: (column) => column);

  GeneratedColumn<String> get parentAccountId => $composableBuilder(
      column: $table.parentAccountId, builder: (column) => column);

  GeneratedColumn<String> get swipesmartCardId => $composableBuilder(
      column: $table.swipesmartCardId, builder: (column) => column);

  GeneratedColumn<String> get avatarPath => $composableBuilder(
      column: $table.avatarPath, builder: (column) => column);

  GeneratedColumn<bool> get includeInTotal => $composableBuilder(
      column: $table.includeInTotal, builder: (column) => column);
}

class $$AccountsTableTableManager extends RootTableManager<
    _$BeeDatabase,
    $AccountsTable,
    Account,
    $$AccountsTableFilterComposer,
    $$AccountsTableOrderingComposer,
    $$AccountsTableAnnotationComposer,
    $$AccountsTableCreateCompanionBuilder,
    $$AccountsTableUpdateCompanionBuilder,
    (Account, BaseReferences<_$BeeDatabase, $AccountsTable, Account>),
    Account,
    PrefetchHooks Function()> {
  $$AccountsTableTableManager(_$BeeDatabase db, $AccountsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AccountsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AccountsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AccountsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<int> ledgerId = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String> type = const Value.absent(),
            Value<String> currency = const Value.absent(),
            Value<double> initialBalance = const Value.absent(),
            Value<DateTime?> createdAt = const Value.absent(),
            Value<DateTime?> updatedAt = const Value.absent(),
            Value<int> sortOrder = const Value.absent(),
            Value<double?> creditLimit = const Value.absent(),
            Value<int?> billingDay = const Value.absent(),
            Value<int?> paymentDueDay = const Value.absent(),
            Value<String?> bankName = const Value.absent(),
            Value<String?> cardLastFour = const Value.absent(),
            Value<String?> note = const Value.absent(),
            Value<String?> syncId = const Value.absent(),
            Value<bool> hidden = const Value.absent(),
            Value<String?> parentAccountId = const Value.absent(),
            Value<String?> swipesmartCardId = const Value.absent(),
            Value<String?> avatarPath = const Value.absent(),
            Value<bool> includeInTotal = const Value.absent(),
          }) =>
              AccountsCompanion(
            id: id,
            ledgerId: ledgerId,
            name: name,
            type: type,
            currency: currency,
            initialBalance: initialBalance,
            createdAt: createdAt,
            updatedAt: updatedAt,
            sortOrder: sortOrder,
            creditLimit: creditLimit,
            billingDay: billingDay,
            paymentDueDay: paymentDueDay,
            bankName: bankName,
            cardLastFour: cardLastFour,
            note: note,
            syncId: syncId,
            hidden: hidden,
            parentAccountId: parentAccountId,
            swipesmartCardId: swipesmartCardId,
            avatarPath: avatarPath,
            includeInTotal: includeInTotal,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required int ledgerId,
            required String name,
            Value<String> type = const Value.absent(),
            Value<String> currency = const Value.absent(),
            Value<double> initialBalance = const Value.absent(),
            Value<DateTime?> createdAt = const Value.absent(),
            Value<DateTime?> updatedAt = const Value.absent(),
            Value<int> sortOrder = const Value.absent(),
            Value<double?> creditLimit = const Value.absent(),
            Value<int?> billingDay = const Value.absent(),
            Value<int?> paymentDueDay = const Value.absent(),
            Value<String?> bankName = const Value.absent(),
            Value<String?> cardLastFour = const Value.absent(),
            Value<String?> note = const Value.absent(),
            Value<String?> syncId = const Value.absent(),
            Value<bool> hidden = const Value.absent(),
            Value<String?> parentAccountId = const Value.absent(),
            Value<String?> swipesmartCardId = const Value.absent(),
            Value<String?> avatarPath = const Value.absent(),
            Value<bool> includeInTotal = const Value.absent(),
          }) =>
              AccountsCompanion.insert(
            id: id,
            ledgerId: ledgerId,
            name: name,
            type: type,
            currency: currency,
            initialBalance: initialBalance,
            createdAt: createdAt,
            updatedAt: updatedAt,
            sortOrder: sortOrder,
            creditLimit: creditLimit,
            billingDay: billingDay,
            paymentDueDay: paymentDueDay,
            bankName: bankName,
            cardLastFour: cardLastFour,
            note: note,
            syncId: syncId,
            hidden: hidden,
            parentAccountId: parentAccountId,
            swipesmartCardId: swipesmartCardId,
            avatarPath: avatarPath,
            includeInTotal: includeInTotal,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$AccountsTableProcessedTableManager = ProcessedTableManager<
    _$BeeDatabase,
    $AccountsTable,
    Account,
    $$AccountsTableFilterComposer,
    $$AccountsTableOrderingComposer,
    $$AccountsTableAnnotationComposer,
    $$AccountsTableCreateCompanionBuilder,
    $$AccountsTableUpdateCompanionBuilder,
    (Account, BaseReferences<_$BeeDatabase, $AccountsTable, Account>),
    Account,
    PrefetchHooks Function()>;
typedef $$CategoriesTableCreateCompanionBuilder = CategoriesCompanion Function({
  Value<int> id,
  required String name,
  required String kind,
  Value<String?> icon,
  Value<int> sortOrder,
  Value<int?> parentId,
  Value<int> level,
  Value<String> iconType,
  Value<String?> customIconPath,
  Value<String?> communityIconId,
  Value<String?> syncId,
});
typedef $$CategoriesTableUpdateCompanionBuilder = CategoriesCompanion Function({
  Value<int> id,
  Value<String> name,
  Value<String> kind,
  Value<String?> icon,
  Value<int> sortOrder,
  Value<int?> parentId,
  Value<int> level,
  Value<String> iconType,
  Value<String?> customIconPath,
  Value<String?> communityIconId,
  Value<String?> syncId,
});

class $$CategoriesTableFilterComposer
    extends Composer<_$BeeDatabase, $CategoriesTable> {
  $$CategoriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get kind => $composableBuilder(
      column: $table.kind, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get icon => $composableBuilder(
      column: $table.icon, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get sortOrder => $composableBuilder(
      column: $table.sortOrder, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get parentId => $composableBuilder(
      column: $table.parentId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get level => $composableBuilder(
      column: $table.level, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get iconType => $composableBuilder(
      column: $table.iconType, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get customIconPath => $composableBuilder(
      column: $table.customIconPath,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get communityIconId => $composableBuilder(
      column: $table.communityIconId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get syncId => $composableBuilder(
      column: $table.syncId, builder: (column) => ColumnFilters(column));
}

class $$CategoriesTableOrderingComposer
    extends Composer<_$BeeDatabase, $CategoriesTable> {
  $$CategoriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get kind => $composableBuilder(
      column: $table.kind, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get icon => $composableBuilder(
      column: $table.icon, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get sortOrder => $composableBuilder(
      column: $table.sortOrder, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get parentId => $composableBuilder(
      column: $table.parentId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get level => $composableBuilder(
      column: $table.level, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get iconType => $composableBuilder(
      column: $table.iconType, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get customIconPath => $composableBuilder(
      column: $table.customIconPath,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get communityIconId => $composableBuilder(
      column: $table.communityIconId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get syncId => $composableBuilder(
      column: $table.syncId, builder: (column) => ColumnOrderings(column));
}

class $$CategoriesTableAnnotationComposer
    extends Composer<_$BeeDatabase, $CategoriesTable> {
  $$CategoriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get icon =>
      $composableBuilder(column: $table.icon, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<int> get parentId =>
      $composableBuilder(column: $table.parentId, builder: (column) => column);

  GeneratedColumn<int> get level =>
      $composableBuilder(column: $table.level, builder: (column) => column);

  GeneratedColumn<String> get iconType =>
      $composableBuilder(column: $table.iconType, builder: (column) => column);

  GeneratedColumn<String> get customIconPath => $composableBuilder(
      column: $table.customIconPath, builder: (column) => column);

  GeneratedColumn<String> get communityIconId => $composableBuilder(
      column: $table.communityIconId, builder: (column) => column);

  GeneratedColumn<String> get syncId =>
      $composableBuilder(column: $table.syncId, builder: (column) => column);
}

class $$CategoriesTableTableManager extends RootTableManager<
    _$BeeDatabase,
    $CategoriesTable,
    Category,
    $$CategoriesTableFilterComposer,
    $$CategoriesTableOrderingComposer,
    $$CategoriesTableAnnotationComposer,
    $$CategoriesTableCreateCompanionBuilder,
    $$CategoriesTableUpdateCompanionBuilder,
    (Category, BaseReferences<_$BeeDatabase, $CategoriesTable, Category>),
    Category,
    PrefetchHooks Function()> {
  $$CategoriesTableTableManager(_$BeeDatabase db, $CategoriesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CategoriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CategoriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CategoriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String> kind = const Value.absent(),
            Value<String?> icon = const Value.absent(),
            Value<int> sortOrder = const Value.absent(),
            Value<int?> parentId = const Value.absent(),
            Value<int> level = const Value.absent(),
            Value<String> iconType = const Value.absent(),
            Value<String?> customIconPath = const Value.absent(),
            Value<String?> communityIconId = const Value.absent(),
            Value<String?> syncId = const Value.absent(),
          }) =>
              CategoriesCompanion(
            id: id,
            name: name,
            kind: kind,
            icon: icon,
            sortOrder: sortOrder,
            parentId: parentId,
            level: level,
            iconType: iconType,
            customIconPath: customIconPath,
            communityIconId: communityIconId,
            syncId: syncId,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String name,
            required String kind,
            Value<String?> icon = const Value.absent(),
            Value<int> sortOrder = const Value.absent(),
            Value<int?> parentId = const Value.absent(),
            Value<int> level = const Value.absent(),
            Value<String> iconType = const Value.absent(),
            Value<String?> customIconPath = const Value.absent(),
            Value<String?> communityIconId = const Value.absent(),
            Value<String?> syncId = const Value.absent(),
          }) =>
              CategoriesCompanion.insert(
            id: id,
            name: name,
            kind: kind,
            icon: icon,
            sortOrder: sortOrder,
            parentId: parentId,
            level: level,
            iconType: iconType,
            customIconPath: customIconPath,
            communityIconId: communityIconId,
            syncId: syncId,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$CategoriesTableProcessedTableManager = ProcessedTableManager<
    _$BeeDatabase,
    $CategoriesTable,
    Category,
    $$CategoriesTableFilterComposer,
    $$CategoriesTableOrderingComposer,
    $$CategoriesTableAnnotationComposer,
    $$CategoriesTableCreateCompanionBuilder,
    $$CategoriesTableUpdateCompanionBuilder,
    (Category, BaseReferences<_$BeeDatabase, $CategoriesTable, Category>),
    Category,
    PrefetchHooks Function()>;
typedef $$TransactionsTableCreateCompanionBuilder = TransactionsCompanion
    Function({
  Value<int> id,
  required int ledgerId,
  required String type,
  required double amount,
  Value<int?> categoryId,
  Value<int?> accountId,
  Value<int?> toAccountId,
  Value<DateTime> happenedAt,
  Value<String?> note,
  Value<String?> syncId,
  Value<String?> createdByUserId,
  Value<String?> lastEditedByUserId,
  Value<String?> categorySyncIdOverride,
  Value<String?> accountSyncIdOverride,
  Value<String?> toAccountSyncIdOverride,
  Value<String?> tagSyncIdsOverride,
  Value<bool> excludeFromStats,
  Value<bool> excludeFromBudget,
  Value<String?> currencyCode,
  Value<double?> nativeAmount,
  Value<String?> merchant,
  Value<String?> refundOfSyncId,
  Value<String?> rewardRuleIdsJson,
  Value<String?> recurringRuleId,
  Value<bool> recurringOccurrenceOverridden,
  Value<DateTime?> reconciledAt,
  Value<DateTime?> deferredPostingAt,
  Value<bool> hasSplits,
  Value<String?> debtSyncId,
  Value<double?> toAmount,
  Value<String?> projectSyncId,
  Value<bool> needsAccountAssignment,
  Value<double?> feeAmount,
  Value<String?> feeLabel,
  Value<double?> discountAmount,
  Value<String?> discountLabel,
});
typedef $$TransactionsTableUpdateCompanionBuilder = TransactionsCompanion
    Function({
  Value<int> id,
  Value<int> ledgerId,
  Value<String> type,
  Value<double> amount,
  Value<int?> categoryId,
  Value<int?> accountId,
  Value<int?> toAccountId,
  Value<DateTime> happenedAt,
  Value<String?> note,
  Value<String?> syncId,
  Value<String?> createdByUserId,
  Value<String?> lastEditedByUserId,
  Value<String?> categorySyncIdOverride,
  Value<String?> accountSyncIdOverride,
  Value<String?> toAccountSyncIdOverride,
  Value<String?> tagSyncIdsOverride,
  Value<bool> excludeFromStats,
  Value<bool> excludeFromBudget,
  Value<String?> currencyCode,
  Value<double?> nativeAmount,
  Value<String?> merchant,
  Value<String?> refundOfSyncId,
  Value<String?> rewardRuleIdsJson,
  Value<String?> recurringRuleId,
  Value<bool> recurringOccurrenceOverridden,
  Value<DateTime?> reconciledAt,
  Value<DateTime?> deferredPostingAt,
  Value<bool> hasSplits,
  Value<String?> debtSyncId,
  Value<double?> toAmount,
  Value<String?> projectSyncId,
  Value<bool> needsAccountAssignment,
  Value<double?> feeAmount,
  Value<String?> feeLabel,
  Value<double?> discountAmount,
  Value<String?> discountLabel,
});

class $$TransactionsTableFilterComposer
    extends Composer<_$BeeDatabase, $TransactionsTable> {
  $$TransactionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get ledgerId => $composableBuilder(
      column: $table.ledgerId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get amount => $composableBuilder(
      column: $table.amount, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get categoryId => $composableBuilder(
      column: $table.categoryId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get accountId => $composableBuilder(
      column: $table.accountId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get toAccountId => $composableBuilder(
      column: $table.toAccountId, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get happenedAt => $composableBuilder(
      column: $table.happenedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get note => $composableBuilder(
      column: $table.note, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get syncId => $composableBuilder(
      column: $table.syncId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get createdByUserId => $composableBuilder(
      column: $table.createdByUserId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get lastEditedByUserId => $composableBuilder(
      column: $table.lastEditedByUserId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get categorySyncIdOverride => $composableBuilder(
      column: $table.categorySyncIdOverride,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get accountSyncIdOverride => $composableBuilder(
      column: $table.accountSyncIdOverride,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get toAccountSyncIdOverride => $composableBuilder(
      column: $table.toAccountSyncIdOverride,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get tagSyncIdsOverride => $composableBuilder(
      column: $table.tagSyncIdsOverride,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get excludeFromStats => $composableBuilder(
      column: $table.excludeFromStats,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get excludeFromBudget => $composableBuilder(
      column: $table.excludeFromBudget,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get currencyCode => $composableBuilder(
      column: $table.currencyCode, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get nativeAmount => $composableBuilder(
      column: $table.nativeAmount, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get merchant => $composableBuilder(
      column: $table.merchant, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get refundOfSyncId => $composableBuilder(
      column: $table.refundOfSyncId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get rewardRuleIdsJson => $composableBuilder(
      column: $table.rewardRuleIdsJson,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get recurringRuleId => $composableBuilder(
      column: $table.recurringRuleId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get recurringOccurrenceOverridden => $composableBuilder(
      column: $table.recurringOccurrenceOverridden,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get reconciledAt => $composableBuilder(
      column: $table.reconciledAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get deferredPostingAt => $composableBuilder(
      column: $table.deferredPostingAt,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get hasSplits => $composableBuilder(
      column: $table.hasSplits, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get debtSyncId => $composableBuilder(
      column: $table.debtSyncId, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get toAmount => $composableBuilder(
      column: $table.toAmount, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get projectSyncId => $composableBuilder(
      column: $table.projectSyncId, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get needsAccountAssignment => $composableBuilder(
      column: $table.needsAccountAssignment,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get feeAmount => $composableBuilder(
      column: $table.feeAmount, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get feeLabel => $composableBuilder(
      column: $table.feeLabel, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get discountAmount => $composableBuilder(
      column: $table.discountAmount,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get discountLabel => $composableBuilder(
      column: $table.discountLabel, builder: (column) => ColumnFilters(column));
}

class $$TransactionsTableOrderingComposer
    extends Composer<_$BeeDatabase, $TransactionsTable> {
  $$TransactionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get ledgerId => $composableBuilder(
      column: $table.ledgerId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get amount => $composableBuilder(
      column: $table.amount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get categoryId => $composableBuilder(
      column: $table.categoryId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get accountId => $composableBuilder(
      column: $table.accountId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get toAccountId => $composableBuilder(
      column: $table.toAccountId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get happenedAt => $composableBuilder(
      column: $table.happenedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get note => $composableBuilder(
      column: $table.note, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get syncId => $composableBuilder(
      column: $table.syncId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get createdByUserId => $composableBuilder(
      column: $table.createdByUserId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get lastEditedByUserId => $composableBuilder(
      column: $table.lastEditedByUserId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get categorySyncIdOverride => $composableBuilder(
      column: $table.categorySyncIdOverride,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get accountSyncIdOverride => $composableBuilder(
      column: $table.accountSyncIdOverride,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get toAccountSyncIdOverride => $composableBuilder(
      column: $table.toAccountSyncIdOverride,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get tagSyncIdsOverride => $composableBuilder(
      column: $table.tagSyncIdsOverride,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get excludeFromStats => $composableBuilder(
      column: $table.excludeFromStats,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get excludeFromBudget => $composableBuilder(
      column: $table.excludeFromBudget,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get currencyCode => $composableBuilder(
      column: $table.currencyCode,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get nativeAmount => $composableBuilder(
      column: $table.nativeAmount,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get merchant => $composableBuilder(
      column: $table.merchant, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get refundOfSyncId => $composableBuilder(
      column: $table.refundOfSyncId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get rewardRuleIdsJson => $composableBuilder(
      column: $table.rewardRuleIdsJson,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get recurringRuleId => $composableBuilder(
      column: $table.recurringRuleId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get recurringOccurrenceOverridden => $composableBuilder(
      column: $table.recurringOccurrenceOverridden,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get reconciledAt => $composableBuilder(
      column: $table.reconciledAt,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get deferredPostingAt => $composableBuilder(
      column: $table.deferredPostingAt,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get hasSplits => $composableBuilder(
      column: $table.hasSplits, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get debtSyncId => $composableBuilder(
      column: $table.debtSyncId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get toAmount => $composableBuilder(
      column: $table.toAmount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get projectSyncId => $composableBuilder(
      column: $table.projectSyncId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get needsAccountAssignment => $composableBuilder(
      column: $table.needsAccountAssignment,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get feeAmount => $composableBuilder(
      column: $table.feeAmount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get feeLabel => $composableBuilder(
      column: $table.feeLabel, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get discountAmount => $composableBuilder(
      column: $table.discountAmount,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get discountLabel => $composableBuilder(
      column: $table.discountLabel,
      builder: (column) => ColumnOrderings(column));
}

class $$TransactionsTableAnnotationComposer
    extends Composer<_$BeeDatabase, $TransactionsTable> {
  $$TransactionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get ledgerId =>
      $composableBuilder(column: $table.ledgerId, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<double> get amount =>
      $composableBuilder(column: $table.amount, builder: (column) => column);

  GeneratedColumn<int> get categoryId => $composableBuilder(
      column: $table.categoryId, builder: (column) => column);

  GeneratedColumn<int> get accountId =>
      $composableBuilder(column: $table.accountId, builder: (column) => column);

  GeneratedColumn<int> get toAccountId => $composableBuilder(
      column: $table.toAccountId, builder: (column) => column);

  GeneratedColumn<DateTime> get happenedAt => $composableBuilder(
      column: $table.happenedAt, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<String> get syncId =>
      $composableBuilder(column: $table.syncId, builder: (column) => column);

  GeneratedColumn<String> get createdByUserId => $composableBuilder(
      column: $table.createdByUserId, builder: (column) => column);

  GeneratedColumn<String> get lastEditedByUserId => $composableBuilder(
      column: $table.lastEditedByUserId, builder: (column) => column);

  GeneratedColumn<String> get categorySyncIdOverride => $composableBuilder(
      column: $table.categorySyncIdOverride, builder: (column) => column);

  GeneratedColumn<String> get accountSyncIdOverride => $composableBuilder(
      column: $table.accountSyncIdOverride, builder: (column) => column);

  GeneratedColumn<String> get toAccountSyncIdOverride => $composableBuilder(
      column: $table.toAccountSyncIdOverride, builder: (column) => column);

  GeneratedColumn<String> get tagSyncIdsOverride => $composableBuilder(
      column: $table.tagSyncIdsOverride, builder: (column) => column);

  GeneratedColumn<bool> get excludeFromStats => $composableBuilder(
      column: $table.excludeFromStats, builder: (column) => column);

  GeneratedColumn<bool> get excludeFromBudget => $composableBuilder(
      column: $table.excludeFromBudget, builder: (column) => column);

  GeneratedColumn<String> get currencyCode => $composableBuilder(
      column: $table.currencyCode, builder: (column) => column);

  GeneratedColumn<double> get nativeAmount => $composableBuilder(
      column: $table.nativeAmount, builder: (column) => column);

  GeneratedColumn<String> get merchant =>
      $composableBuilder(column: $table.merchant, builder: (column) => column);

  GeneratedColumn<String> get refundOfSyncId => $composableBuilder(
      column: $table.refundOfSyncId, builder: (column) => column);

  GeneratedColumn<String> get rewardRuleIdsJson => $composableBuilder(
      column: $table.rewardRuleIdsJson, builder: (column) => column);

  GeneratedColumn<String> get recurringRuleId => $composableBuilder(
      column: $table.recurringRuleId, builder: (column) => column);

  GeneratedColumn<bool> get recurringOccurrenceOverridden => $composableBuilder(
      column: $table.recurringOccurrenceOverridden,
      builder: (column) => column);

  GeneratedColumn<DateTime> get reconciledAt => $composableBuilder(
      column: $table.reconciledAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deferredPostingAt => $composableBuilder(
      column: $table.deferredPostingAt, builder: (column) => column);

  GeneratedColumn<bool> get hasSplits =>
      $composableBuilder(column: $table.hasSplits, builder: (column) => column);

  GeneratedColumn<String> get debtSyncId => $composableBuilder(
      column: $table.debtSyncId, builder: (column) => column);

  GeneratedColumn<double> get toAmount =>
      $composableBuilder(column: $table.toAmount, builder: (column) => column);

  GeneratedColumn<String> get projectSyncId => $composableBuilder(
      column: $table.projectSyncId, builder: (column) => column);

  GeneratedColumn<bool> get needsAccountAssignment => $composableBuilder(
      column: $table.needsAccountAssignment, builder: (column) => column);

  GeneratedColumn<double> get feeAmount =>
      $composableBuilder(column: $table.feeAmount, builder: (column) => column);

  GeneratedColumn<String> get feeLabel =>
      $composableBuilder(column: $table.feeLabel, builder: (column) => column);

  GeneratedColumn<double> get discountAmount => $composableBuilder(
      column: $table.discountAmount, builder: (column) => column);

  GeneratedColumn<String> get discountLabel => $composableBuilder(
      column: $table.discountLabel, builder: (column) => column);
}

class $$TransactionsTableTableManager extends RootTableManager<
    _$BeeDatabase,
    $TransactionsTable,
    Transaction,
    $$TransactionsTableFilterComposer,
    $$TransactionsTableOrderingComposer,
    $$TransactionsTableAnnotationComposer,
    $$TransactionsTableCreateCompanionBuilder,
    $$TransactionsTableUpdateCompanionBuilder,
    (
      Transaction,
      BaseReferences<_$BeeDatabase, $TransactionsTable, Transaction>
    ),
    Transaction,
    PrefetchHooks Function()> {
  $$TransactionsTableTableManager(_$BeeDatabase db, $TransactionsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TransactionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TransactionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TransactionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<int> ledgerId = const Value.absent(),
            Value<String> type = const Value.absent(),
            Value<double> amount = const Value.absent(),
            Value<int?> categoryId = const Value.absent(),
            Value<int?> accountId = const Value.absent(),
            Value<int?> toAccountId = const Value.absent(),
            Value<DateTime> happenedAt = const Value.absent(),
            Value<String?> note = const Value.absent(),
            Value<String?> syncId = const Value.absent(),
            Value<String?> createdByUserId = const Value.absent(),
            Value<String?> lastEditedByUserId = const Value.absent(),
            Value<String?> categorySyncIdOverride = const Value.absent(),
            Value<String?> accountSyncIdOverride = const Value.absent(),
            Value<String?> toAccountSyncIdOverride = const Value.absent(),
            Value<String?> tagSyncIdsOverride = const Value.absent(),
            Value<bool> excludeFromStats = const Value.absent(),
            Value<bool> excludeFromBudget = const Value.absent(),
            Value<String?> currencyCode = const Value.absent(),
            Value<double?> nativeAmount = const Value.absent(),
            Value<String?> merchant = const Value.absent(),
            Value<String?> refundOfSyncId = const Value.absent(),
            Value<String?> rewardRuleIdsJson = const Value.absent(),
            Value<String?> recurringRuleId = const Value.absent(),
            Value<bool> recurringOccurrenceOverridden = const Value.absent(),
            Value<DateTime?> reconciledAt = const Value.absent(),
            Value<DateTime?> deferredPostingAt = const Value.absent(),
            Value<bool> hasSplits = const Value.absent(),
            Value<String?> debtSyncId = const Value.absent(),
            Value<double?> toAmount = const Value.absent(),
            Value<String?> projectSyncId = const Value.absent(),
            Value<bool> needsAccountAssignment = const Value.absent(),
            Value<double?> feeAmount = const Value.absent(),
            Value<String?> feeLabel = const Value.absent(),
            Value<double?> discountAmount = const Value.absent(),
            Value<String?> discountLabel = const Value.absent(),
          }) =>
              TransactionsCompanion(
            id: id,
            ledgerId: ledgerId,
            type: type,
            amount: amount,
            categoryId: categoryId,
            accountId: accountId,
            toAccountId: toAccountId,
            happenedAt: happenedAt,
            note: note,
            syncId: syncId,
            createdByUserId: createdByUserId,
            lastEditedByUserId: lastEditedByUserId,
            categorySyncIdOverride: categorySyncIdOverride,
            accountSyncIdOverride: accountSyncIdOverride,
            toAccountSyncIdOverride: toAccountSyncIdOverride,
            tagSyncIdsOverride: tagSyncIdsOverride,
            excludeFromStats: excludeFromStats,
            excludeFromBudget: excludeFromBudget,
            currencyCode: currencyCode,
            nativeAmount: nativeAmount,
            merchant: merchant,
            refundOfSyncId: refundOfSyncId,
            rewardRuleIdsJson: rewardRuleIdsJson,
            recurringRuleId: recurringRuleId,
            recurringOccurrenceOverridden: recurringOccurrenceOverridden,
            reconciledAt: reconciledAt,
            deferredPostingAt: deferredPostingAt,
            hasSplits: hasSplits,
            debtSyncId: debtSyncId,
            toAmount: toAmount,
            projectSyncId: projectSyncId,
            needsAccountAssignment: needsAccountAssignment,
            feeAmount: feeAmount,
            feeLabel: feeLabel,
            discountAmount: discountAmount,
            discountLabel: discountLabel,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required int ledgerId,
            required String type,
            required double amount,
            Value<int?> categoryId = const Value.absent(),
            Value<int?> accountId = const Value.absent(),
            Value<int?> toAccountId = const Value.absent(),
            Value<DateTime> happenedAt = const Value.absent(),
            Value<String?> note = const Value.absent(),
            Value<String?> syncId = const Value.absent(),
            Value<String?> createdByUserId = const Value.absent(),
            Value<String?> lastEditedByUserId = const Value.absent(),
            Value<String?> categorySyncIdOverride = const Value.absent(),
            Value<String?> accountSyncIdOverride = const Value.absent(),
            Value<String?> toAccountSyncIdOverride = const Value.absent(),
            Value<String?> tagSyncIdsOverride = const Value.absent(),
            Value<bool> excludeFromStats = const Value.absent(),
            Value<bool> excludeFromBudget = const Value.absent(),
            Value<String?> currencyCode = const Value.absent(),
            Value<double?> nativeAmount = const Value.absent(),
            Value<String?> merchant = const Value.absent(),
            Value<String?> refundOfSyncId = const Value.absent(),
            Value<String?> rewardRuleIdsJson = const Value.absent(),
            Value<String?> recurringRuleId = const Value.absent(),
            Value<bool> recurringOccurrenceOverridden = const Value.absent(),
            Value<DateTime?> reconciledAt = const Value.absent(),
            Value<DateTime?> deferredPostingAt = const Value.absent(),
            Value<bool> hasSplits = const Value.absent(),
            Value<String?> debtSyncId = const Value.absent(),
            Value<double?> toAmount = const Value.absent(),
            Value<String?> projectSyncId = const Value.absent(),
            Value<bool> needsAccountAssignment = const Value.absent(),
            Value<double?> feeAmount = const Value.absent(),
            Value<String?> feeLabel = const Value.absent(),
            Value<double?> discountAmount = const Value.absent(),
            Value<String?> discountLabel = const Value.absent(),
          }) =>
              TransactionsCompanion.insert(
            id: id,
            ledgerId: ledgerId,
            type: type,
            amount: amount,
            categoryId: categoryId,
            accountId: accountId,
            toAccountId: toAccountId,
            happenedAt: happenedAt,
            note: note,
            syncId: syncId,
            createdByUserId: createdByUserId,
            lastEditedByUserId: lastEditedByUserId,
            categorySyncIdOverride: categorySyncIdOverride,
            accountSyncIdOverride: accountSyncIdOverride,
            toAccountSyncIdOverride: toAccountSyncIdOverride,
            tagSyncIdsOverride: tagSyncIdsOverride,
            excludeFromStats: excludeFromStats,
            excludeFromBudget: excludeFromBudget,
            currencyCode: currencyCode,
            nativeAmount: nativeAmount,
            merchant: merchant,
            refundOfSyncId: refundOfSyncId,
            rewardRuleIdsJson: rewardRuleIdsJson,
            recurringRuleId: recurringRuleId,
            recurringOccurrenceOverridden: recurringOccurrenceOverridden,
            reconciledAt: reconciledAt,
            deferredPostingAt: deferredPostingAt,
            hasSplits: hasSplits,
            debtSyncId: debtSyncId,
            toAmount: toAmount,
            projectSyncId: projectSyncId,
            needsAccountAssignment: needsAccountAssignment,
            feeAmount: feeAmount,
            feeLabel: feeLabel,
            discountAmount: discountAmount,
            discountLabel: discountLabel,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$TransactionsTableProcessedTableManager = ProcessedTableManager<
    _$BeeDatabase,
    $TransactionsTable,
    Transaction,
    $$TransactionsTableFilterComposer,
    $$TransactionsTableOrderingComposer,
    $$TransactionsTableAnnotationComposer,
    $$TransactionsTableCreateCompanionBuilder,
    $$TransactionsTableUpdateCompanionBuilder,
    (
      Transaction,
      BaseReferences<_$BeeDatabase, $TransactionsTable, Transaction>
    ),
    Transaction,
    PrefetchHooks Function()>;
typedef $$RecurringTransactionsTableCreateCompanionBuilder
    = RecurringTransactionsCompanion Function({
  Value<int> id,
  Value<String?> syncId,
  required int ledgerId,
  required String type,
  required double amount,
  Value<int?> categoryId,
  Value<int?> accountId,
  Value<int?> fromAccountId,
  Value<int?> toAccountId,
  Value<String?> note,
  Value<String?> merchant,
  Value<String?> tagSyncIdsJson,
  Value<String?> rewardRuleIdsJson,
  required String frequency,
  Value<int> interval,
  Value<String?> advancedRuleJson,
  required DateTime nextRunAt,
  Value<DateTime?> endAt,
  Value<DateTime?> generatedUntilAt,
  Value<bool> enabled,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
});
typedef $$RecurringTransactionsTableUpdateCompanionBuilder
    = RecurringTransactionsCompanion Function({
  Value<int> id,
  Value<String?> syncId,
  Value<int> ledgerId,
  Value<String> type,
  Value<double> amount,
  Value<int?> categoryId,
  Value<int?> accountId,
  Value<int?> fromAccountId,
  Value<int?> toAccountId,
  Value<String?> note,
  Value<String?> merchant,
  Value<String?> tagSyncIdsJson,
  Value<String?> rewardRuleIdsJson,
  Value<String> frequency,
  Value<int> interval,
  Value<String?> advancedRuleJson,
  Value<DateTime> nextRunAt,
  Value<DateTime?> endAt,
  Value<DateTime?> generatedUntilAt,
  Value<bool> enabled,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
});

class $$RecurringTransactionsTableFilterComposer
    extends Composer<_$BeeDatabase, $RecurringTransactionsTable> {
  $$RecurringTransactionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get syncId => $composableBuilder(
      column: $table.syncId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get ledgerId => $composableBuilder(
      column: $table.ledgerId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get amount => $composableBuilder(
      column: $table.amount, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get categoryId => $composableBuilder(
      column: $table.categoryId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get accountId => $composableBuilder(
      column: $table.accountId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get fromAccountId => $composableBuilder(
      column: $table.fromAccountId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get toAccountId => $composableBuilder(
      column: $table.toAccountId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get note => $composableBuilder(
      column: $table.note, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get merchant => $composableBuilder(
      column: $table.merchant, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get tagSyncIdsJson => $composableBuilder(
      column: $table.tagSyncIdsJson,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get rewardRuleIdsJson => $composableBuilder(
      column: $table.rewardRuleIdsJson,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get frequency => $composableBuilder(
      column: $table.frequency, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get interval => $composableBuilder(
      column: $table.interval, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get advancedRuleJson => $composableBuilder(
      column: $table.advancedRuleJson,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get nextRunAt => $composableBuilder(
      column: $table.nextRunAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get endAt => $composableBuilder(
      column: $table.endAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get generatedUntilAt => $composableBuilder(
      column: $table.generatedUntilAt,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get enabled => $composableBuilder(
      column: $table.enabled, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$RecurringTransactionsTableOrderingComposer
    extends Composer<_$BeeDatabase, $RecurringTransactionsTable> {
  $$RecurringTransactionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get syncId => $composableBuilder(
      column: $table.syncId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get ledgerId => $composableBuilder(
      column: $table.ledgerId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get amount => $composableBuilder(
      column: $table.amount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get categoryId => $composableBuilder(
      column: $table.categoryId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get accountId => $composableBuilder(
      column: $table.accountId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get fromAccountId => $composableBuilder(
      column: $table.fromAccountId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get toAccountId => $composableBuilder(
      column: $table.toAccountId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get note => $composableBuilder(
      column: $table.note, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get merchant => $composableBuilder(
      column: $table.merchant, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get tagSyncIdsJson => $composableBuilder(
      column: $table.tagSyncIdsJson,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get rewardRuleIdsJson => $composableBuilder(
      column: $table.rewardRuleIdsJson,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get frequency => $composableBuilder(
      column: $table.frequency, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get interval => $composableBuilder(
      column: $table.interval, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get advancedRuleJson => $composableBuilder(
      column: $table.advancedRuleJson,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get nextRunAt => $composableBuilder(
      column: $table.nextRunAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get endAt => $composableBuilder(
      column: $table.endAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get generatedUntilAt => $composableBuilder(
      column: $table.generatedUntilAt,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get enabled => $composableBuilder(
      column: $table.enabled, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$RecurringTransactionsTableAnnotationComposer
    extends Composer<_$BeeDatabase, $RecurringTransactionsTable> {
  $$RecurringTransactionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get syncId =>
      $composableBuilder(column: $table.syncId, builder: (column) => column);

  GeneratedColumn<int> get ledgerId =>
      $composableBuilder(column: $table.ledgerId, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<double> get amount =>
      $composableBuilder(column: $table.amount, builder: (column) => column);

  GeneratedColumn<int> get categoryId => $composableBuilder(
      column: $table.categoryId, builder: (column) => column);

  GeneratedColumn<int> get accountId =>
      $composableBuilder(column: $table.accountId, builder: (column) => column);

  GeneratedColumn<int> get fromAccountId => $composableBuilder(
      column: $table.fromAccountId, builder: (column) => column);

  GeneratedColumn<int> get toAccountId => $composableBuilder(
      column: $table.toAccountId, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<String> get merchant =>
      $composableBuilder(column: $table.merchant, builder: (column) => column);

  GeneratedColumn<String> get tagSyncIdsJson => $composableBuilder(
      column: $table.tagSyncIdsJson, builder: (column) => column);

  GeneratedColumn<String> get rewardRuleIdsJson => $composableBuilder(
      column: $table.rewardRuleIdsJson, builder: (column) => column);

  GeneratedColumn<String> get frequency =>
      $composableBuilder(column: $table.frequency, builder: (column) => column);

  GeneratedColumn<int> get interval =>
      $composableBuilder(column: $table.interval, builder: (column) => column);

  GeneratedColumn<String> get advancedRuleJson => $composableBuilder(
      column: $table.advancedRuleJson, builder: (column) => column);

  GeneratedColumn<DateTime> get nextRunAt =>
      $composableBuilder(column: $table.nextRunAt, builder: (column) => column);

  GeneratedColumn<DateTime> get endAt =>
      $composableBuilder(column: $table.endAt, builder: (column) => column);

  GeneratedColumn<DateTime> get generatedUntilAt => $composableBuilder(
      column: $table.generatedUntilAt, builder: (column) => column);

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$RecurringTransactionsTableTableManager extends RootTableManager<
    _$BeeDatabase,
    $RecurringTransactionsTable,
    RecurringTransaction,
    $$RecurringTransactionsTableFilterComposer,
    $$RecurringTransactionsTableOrderingComposer,
    $$RecurringTransactionsTableAnnotationComposer,
    $$RecurringTransactionsTableCreateCompanionBuilder,
    $$RecurringTransactionsTableUpdateCompanionBuilder,
    (
      RecurringTransaction,
      BaseReferences<_$BeeDatabase, $RecurringTransactionsTable,
          RecurringTransaction>
    ),
    RecurringTransaction,
    PrefetchHooks Function()> {
  $$RecurringTransactionsTableTableManager(
      _$BeeDatabase db, $RecurringTransactionsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RecurringTransactionsTableFilterComposer(
                  $db: db, $table: table),
          createOrderingComposer: () =>
              $$RecurringTransactionsTableOrderingComposer(
                  $db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RecurringTransactionsTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String?> syncId = const Value.absent(),
            Value<int> ledgerId = const Value.absent(),
            Value<String> type = const Value.absent(),
            Value<double> amount = const Value.absent(),
            Value<int?> categoryId = const Value.absent(),
            Value<int?> accountId = const Value.absent(),
            Value<int?> fromAccountId = const Value.absent(),
            Value<int?> toAccountId = const Value.absent(),
            Value<String?> note = const Value.absent(),
            Value<String?> merchant = const Value.absent(),
            Value<String?> tagSyncIdsJson = const Value.absent(),
            Value<String?> rewardRuleIdsJson = const Value.absent(),
            Value<String> frequency = const Value.absent(),
            Value<int> interval = const Value.absent(),
            Value<String?> advancedRuleJson = const Value.absent(),
            Value<DateTime> nextRunAt = const Value.absent(),
            Value<DateTime?> endAt = const Value.absent(),
            Value<DateTime?> generatedUntilAt = const Value.absent(),
            Value<bool> enabled = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
          }) =>
              RecurringTransactionsCompanion(
            id: id,
            syncId: syncId,
            ledgerId: ledgerId,
            type: type,
            amount: amount,
            categoryId: categoryId,
            accountId: accountId,
            fromAccountId: fromAccountId,
            toAccountId: toAccountId,
            note: note,
            merchant: merchant,
            tagSyncIdsJson: tagSyncIdsJson,
            rewardRuleIdsJson: rewardRuleIdsJson,
            frequency: frequency,
            interval: interval,
            advancedRuleJson: advancedRuleJson,
            nextRunAt: nextRunAt,
            endAt: endAt,
            generatedUntilAt: generatedUntilAt,
            enabled: enabled,
            createdAt: createdAt,
            updatedAt: updatedAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String?> syncId = const Value.absent(),
            required int ledgerId,
            required String type,
            required double amount,
            Value<int?> categoryId = const Value.absent(),
            Value<int?> accountId = const Value.absent(),
            Value<int?> fromAccountId = const Value.absent(),
            Value<int?> toAccountId = const Value.absent(),
            Value<String?> note = const Value.absent(),
            Value<String?> merchant = const Value.absent(),
            Value<String?> tagSyncIdsJson = const Value.absent(),
            Value<String?> rewardRuleIdsJson = const Value.absent(),
            required String frequency,
            Value<int> interval = const Value.absent(),
            Value<String?> advancedRuleJson = const Value.absent(),
            required DateTime nextRunAt,
            Value<DateTime?> endAt = const Value.absent(),
            Value<DateTime?> generatedUntilAt = const Value.absent(),
            Value<bool> enabled = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
          }) =>
              RecurringTransactionsCompanion.insert(
            id: id,
            syncId: syncId,
            ledgerId: ledgerId,
            type: type,
            amount: amount,
            categoryId: categoryId,
            accountId: accountId,
            fromAccountId: fromAccountId,
            toAccountId: toAccountId,
            note: note,
            merchant: merchant,
            tagSyncIdsJson: tagSyncIdsJson,
            rewardRuleIdsJson: rewardRuleIdsJson,
            frequency: frequency,
            interval: interval,
            advancedRuleJson: advancedRuleJson,
            nextRunAt: nextRunAt,
            endAt: endAt,
            generatedUntilAt: generatedUntilAt,
            enabled: enabled,
            createdAt: createdAt,
            updatedAt: updatedAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$RecurringTransactionsTableProcessedTableManager
    = ProcessedTableManager<
        _$BeeDatabase,
        $RecurringTransactionsTable,
        RecurringTransaction,
        $$RecurringTransactionsTableFilterComposer,
        $$RecurringTransactionsTableOrderingComposer,
        $$RecurringTransactionsTableAnnotationComposer,
        $$RecurringTransactionsTableCreateCompanionBuilder,
        $$RecurringTransactionsTableUpdateCompanionBuilder,
        (
          RecurringTransaction,
          BaseReferences<_$BeeDatabase, $RecurringTransactionsTable,
              RecurringTransaction>
        ),
        RecurringTransaction,
        PrefetchHooks Function()>;
typedef $$ConversationsTableCreateCompanionBuilder = ConversationsCompanion
    Function({
  Value<int> id,
  Value<int?> ledgerId,
  Value<String> title,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
});
typedef $$ConversationsTableUpdateCompanionBuilder = ConversationsCompanion
    Function({
  Value<int> id,
  Value<int?> ledgerId,
  Value<String> title,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
});

class $$ConversationsTableFilterComposer
    extends Composer<_$BeeDatabase, $ConversationsTable> {
  $$ConversationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get ledgerId => $composableBuilder(
      column: $table.ledgerId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$ConversationsTableOrderingComposer
    extends Composer<_$BeeDatabase, $ConversationsTable> {
  $$ConversationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get ledgerId => $composableBuilder(
      column: $table.ledgerId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$ConversationsTableAnnotationComposer
    extends Composer<_$BeeDatabase, $ConversationsTable> {
  $$ConversationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get ledgerId =>
      $composableBuilder(column: $table.ledgerId, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$ConversationsTableTableManager extends RootTableManager<
    _$BeeDatabase,
    $ConversationsTable,
    Conversation,
    $$ConversationsTableFilterComposer,
    $$ConversationsTableOrderingComposer,
    $$ConversationsTableAnnotationComposer,
    $$ConversationsTableCreateCompanionBuilder,
    $$ConversationsTableUpdateCompanionBuilder,
    (
      Conversation,
      BaseReferences<_$BeeDatabase, $ConversationsTable, Conversation>
    ),
    Conversation,
    PrefetchHooks Function()> {
  $$ConversationsTableTableManager(_$BeeDatabase db, $ConversationsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ConversationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ConversationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ConversationsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<int?> ledgerId = const Value.absent(),
            Value<String> title = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
          }) =>
              ConversationsCompanion(
            id: id,
            ledgerId: ledgerId,
            title: title,
            createdAt: createdAt,
            updatedAt: updatedAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<int?> ledgerId = const Value.absent(),
            Value<String> title = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
          }) =>
              ConversationsCompanion.insert(
            id: id,
            ledgerId: ledgerId,
            title: title,
            createdAt: createdAt,
            updatedAt: updatedAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$ConversationsTableProcessedTableManager = ProcessedTableManager<
    _$BeeDatabase,
    $ConversationsTable,
    Conversation,
    $$ConversationsTableFilterComposer,
    $$ConversationsTableOrderingComposer,
    $$ConversationsTableAnnotationComposer,
    $$ConversationsTableCreateCompanionBuilder,
    $$ConversationsTableUpdateCompanionBuilder,
    (
      Conversation,
      BaseReferences<_$BeeDatabase, $ConversationsTable, Conversation>
    ),
    Conversation,
    PrefetchHooks Function()>;
typedef $$MessagesTableCreateCompanionBuilder = MessagesCompanion Function({
  Value<int> id,
  required int conversationId,
  required String role,
  required String content,
  required String messageType,
  Value<String?> metadata,
  Value<int?> transactionId,
  Value<DateTime> createdAt,
});
typedef $$MessagesTableUpdateCompanionBuilder = MessagesCompanion Function({
  Value<int> id,
  Value<int> conversationId,
  Value<String> role,
  Value<String> content,
  Value<String> messageType,
  Value<String?> metadata,
  Value<int?> transactionId,
  Value<DateTime> createdAt,
});

class $$MessagesTableFilterComposer
    extends Composer<_$BeeDatabase, $MessagesTable> {
  $$MessagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get conversationId => $composableBuilder(
      column: $table.conversationId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get role => $composableBuilder(
      column: $table.role, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get content => $composableBuilder(
      column: $table.content, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get messageType => $composableBuilder(
      column: $table.messageType, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get metadata => $composableBuilder(
      column: $table.metadata, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get transactionId => $composableBuilder(
      column: $table.transactionId, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));
}

class $$MessagesTableOrderingComposer
    extends Composer<_$BeeDatabase, $MessagesTable> {
  $$MessagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get conversationId => $composableBuilder(
      column: $table.conversationId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get role => $composableBuilder(
      column: $table.role, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get content => $composableBuilder(
      column: $table.content, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get messageType => $composableBuilder(
      column: $table.messageType, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get metadata => $composableBuilder(
      column: $table.metadata, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get transactionId => $composableBuilder(
      column: $table.transactionId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));
}

class $$MessagesTableAnnotationComposer
    extends Composer<_$BeeDatabase, $MessagesTable> {
  $$MessagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get conversationId => $composableBuilder(
      column: $table.conversationId, builder: (column) => column);

  GeneratedColumn<String> get role =>
      $composableBuilder(column: $table.role, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<String> get messageType => $composableBuilder(
      column: $table.messageType, builder: (column) => column);

  GeneratedColumn<String> get metadata =>
      $composableBuilder(column: $table.metadata, builder: (column) => column);

  GeneratedColumn<int> get transactionId => $composableBuilder(
      column: $table.transactionId, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$MessagesTableTableManager extends RootTableManager<
    _$BeeDatabase,
    $MessagesTable,
    Message,
    $$MessagesTableFilterComposer,
    $$MessagesTableOrderingComposer,
    $$MessagesTableAnnotationComposer,
    $$MessagesTableCreateCompanionBuilder,
    $$MessagesTableUpdateCompanionBuilder,
    (Message, BaseReferences<_$BeeDatabase, $MessagesTable, Message>),
    Message,
    PrefetchHooks Function()> {
  $$MessagesTableTableManager(_$BeeDatabase db, $MessagesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MessagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MessagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MessagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<int> conversationId = const Value.absent(),
            Value<String> role = const Value.absent(),
            Value<String> content = const Value.absent(),
            Value<String> messageType = const Value.absent(),
            Value<String?> metadata = const Value.absent(),
            Value<int?> transactionId = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
          }) =>
              MessagesCompanion(
            id: id,
            conversationId: conversationId,
            role: role,
            content: content,
            messageType: messageType,
            metadata: metadata,
            transactionId: transactionId,
            createdAt: createdAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required int conversationId,
            required String role,
            required String content,
            required String messageType,
            Value<String?> metadata = const Value.absent(),
            Value<int?> transactionId = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
          }) =>
              MessagesCompanion.insert(
            id: id,
            conversationId: conversationId,
            role: role,
            content: content,
            messageType: messageType,
            metadata: metadata,
            transactionId: transactionId,
            createdAt: createdAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$MessagesTableProcessedTableManager = ProcessedTableManager<
    _$BeeDatabase,
    $MessagesTable,
    Message,
    $$MessagesTableFilterComposer,
    $$MessagesTableOrderingComposer,
    $$MessagesTableAnnotationComposer,
    $$MessagesTableCreateCompanionBuilder,
    $$MessagesTableUpdateCompanionBuilder,
    (Message, BaseReferences<_$BeeDatabase, $MessagesTable, Message>),
    Message,
    PrefetchHooks Function()>;
typedef $$TagsTableCreateCompanionBuilder = TagsCompanion Function({
  Value<int> id,
  required String name,
  Value<String?> color,
  Value<int> sortOrder,
  Value<DateTime> createdAt,
  Value<String?> syncId,
});
typedef $$TagsTableUpdateCompanionBuilder = TagsCompanion Function({
  Value<int> id,
  Value<String> name,
  Value<String?> color,
  Value<int> sortOrder,
  Value<DateTime> createdAt,
  Value<String?> syncId,
});

class $$TagsTableFilterComposer extends Composer<_$BeeDatabase, $TagsTable> {
  $$TagsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get color => $composableBuilder(
      column: $table.color, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get sortOrder => $composableBuilder(
      column: $table.sortOrder, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get syncId => $composableBuilder(
      column: $table.syncId, builder: (column) => ColumnFilters(column));
}

class $$TagsTableOrderingComposer extends Composer<_$BeeDatabase, $TagsTable> {
  $$TagsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get color => $composableBuilder(
      column: $table.color, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get sortOrder => $composableBuilder(
      column: $table.sortOrder, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get syncId => $composableBuilder(
      column: $table.syncId, builder: (column) => ColumnOrderings(column));
}

class $$TagsTableAnnotationComposer
    extends Composer<_$BeeDatabase, $TagsTable> {
  $$TagsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get color =>
      $composableBuilder(column: $table.color, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get syncId =>
      $composableBuilder(column: $table.syncId, builder: (column) => column);
}

class $$TagsTableTableManager extends RootTableManager<
    _$BeeDatabase,
    $TagsTable,
    Tag,
    $$TagsTableFilterComposer,
    $$TagsTableOrderingComposer,
    $$TagsTableAnnotationComposer,
    $$TagsTableCreateCompanionBuilder,
    $$TagsTableUpdateCompanionBuilder,
    (Tag, BaseReferences<_$BeeDatabase, $TagsTable, Tag>),
    Tag,
    PrefetchHooks Function()> {
  $$TagsTableTableManager(_$BeeDatabase db, $TagsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TagsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TagsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TagsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String?> color = const Value.absent(),
            Value<int> sortOrder = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<String?> syncId = const Value.absent(),
          }) =>
              TagsCompanion(
            id: id,
            name: name,
            color: color,
            sortOrder: sortOrder,
            createdAt: createdAt,
            syncId: syncId,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String name,
            Value<String?> color = const Value.absent(),
            Value<int> sortOrder = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<String?> syncId = const Value.absent(),
          }) =>
              TagsCompanion.insert(
            id: id,
            name: name,
            color: color,
            sortOrder: sortOrder,
            createdAt: createdAt,
            syncId: syncId,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$TagsTableProcessedTableManager = ProcessedTableManager<
    _$BeeDatabase,
    $TagsTable,
    Tag,
    $$TagsTableFilterComposer,
    $$TagsTableOrderingComposer,
    $$TagsTableAnnotationComposer,
    $$TagsTableCreateCompanionBuilder,
    $$TagsTableUpdateCompanionBuilder,
    (Tag, BaseReferences<_$BeeDatabase, $TagsTable, Tag>),
    Tag,
    PrefetchHooks Function()>;
typedef $$TransactionTagsTableCreateCompanionBuilder = TransactionTagsCompanion
    Function({
  Value<int> id,
  required int transactionId,
  required int tagId,
});
typedef $$TransactionTagsTableUpdateCompanionBuilder = TransactionTagsCompanion
    Function({
  Value<int> id,
  Value<int> transactionId,
  Value<int> tagId,
});

class $$TransactionTagsTableFilterComposer
    extends Composer<_$BeeDatabase, $TransactionTagsTable> {
  $$TransactionTagsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get transactionId => $composableBuilder(
      column: $table.transactionId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get tagId => $composableBuilder(
      column: $table.tagId, builder: (column) => ColumnFilters(column));
}

class $$TransactionTagsTableOrderingComposer
    extends Composer<_$BeeDatabase, $TransactionTagsTable> {
  $$TransactionTagsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get transactionId => $composableBuilder(
      column: $table.transactionId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get tagId => $composableBuilder(
      column: $table.tagId, builder: (column) => ColumnOrderings(column));
}

class $$TransactionTagsTableAnnotationComposer
    extends Composer<_$BeeDatabase, $TransactionTagsTable> {
  $$TransactionTagsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get transactionId => $composableBuilder(
      column: $table.transactionId, builder: (column) => column);

  GeneratedColumn<int> get tagId =>
      $composableBuilder(column: $table.tagId, builder: (column) => column);
}

class $$TransactionTagsTableTableManager extends RootTableManager<
    _$BeeDatabase,
    $TransactionTagsTable,
    TransactionTag,
    $$TransactionTagsTableFilterComposer,
    $$TransactionTagsTableOrderingComposer,
    $$TransactionTagsTableAnnotationComposer,
    $$TransactionTagsTableCreateCompanionBuilder,
    $$TransactionTagsTableUpdateCompanionBuilder,
    (
      TransactionTag,
      BaseReferences<_$BeeDatabase, $TransactionTagsTable, TransactionTag>
    ),
    TransactionTag,
    PrefetchHooks Function()> {
  $$TransactionTagsTableTableManager(
      _$BeeDatabase db, $TransactionTagsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TransactionTagsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TransactionTagsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TransactionTagsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<int> transactionId = const Value.absent(),
            Value<int> tagId = const Value.absent(),
          }) =>
              TransactionTagsCompanion(
            id: id,
            transactionId: transactionId,
            tagId: tagId,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required int transactionId,
            required int tagId,
          }) =>
              TransactionTagsCompanion.insert(
            id: id,
            transactionId: transactionId,
            tagId: tagId,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$TransactionTagsTableProcessedTableManager = ProcessedTableManager<
    _$BeeDatabase,
    $TransactionTagsTable,
    TransactionTag,
    $$TransactionTagsTableFilterComposer,
    $$TransactionTagsTableOrderingComposer,
    $$TransactionTagsTableAnnotationComposer,
    $$TransactionTagsTableCreateCompanionBuilder,
    $$TransactionTagsTableUpdateCompanionBuilder,
    (
      TransactionTag,
      BaseReferences<_$BeeDatabase, $TransactionTagsTable, TransactionTag>
    ),
    TransactionTag,
    PrefetchHooks Function()>;
typedef $$BudgetsTableCreateCompanionBuilder = BudgetsCompanion Function({
  Value<int> id,
  Value<String?> syncId,
  required int ledgerId,
  Value<String> type,
  Value<int?> categoryId,
  required double amount,
  Value<String> period,
  Value<int> startDay,
  Value<bool> enabled,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
});
typedef $$BudgetsTableUpdateCompanionBuilder = BudgetsCompanion Function({
  Value<int> id,
  Value<String?> syncId,
  Value<int> ledgerId,
  Value<String> type,
  Value<int?> categoryId,
  Value<double> amount,
  Value<String> period,
  Value<int> startDay,
  Value<bool> enabled,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
});

class $$BudgetsTableFilterComposer
    extends Composer<_$BeeDatabase, $BudgetsTable> {
  $$BudgetsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get syncId => $composableBuilder(
      column: $table.syncId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get ledgerId => $composableBuilder(
      column: $table.ledgerId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get categoryId => $composableBuilder(
      column: $table.categoryId, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get amount => $composableBuilder(
      column: $table.amount, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get period => $composableBuilder(
      column: $table.period, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get startDay => $composableBuilder(
      column: $table.startDay, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get enabled => $composableBuilder(
      column: $table.enabled, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$BudgetsTableOrderingComposer
    extends Composer<_$BeeDatabase, $BudgetsTable> {
  $$BudgetsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get syncId => $composableBuilder(
      column: $table.syncId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get ledgerId => $composableBuilder(
      column: $table.ledgerId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get categoryId => $composableBuilder(
      column: $table.categoryId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get amount => $composableBuilder(
      column: $table.amount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get period => $composableBuilder(
      column: $table.period, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get startDay => $composableBuilder(
      column: $table.startDay, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get enabled => $composableBuilder(
      column: $table.enabled, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$BudgetsTableAnnotationComposer
    extends Composer<_$BeeDatabase, $BudgetsTable> {
  $$BudgetsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get syncId =>
      $composableBuilder(column: $table.syncId, builder: (column) => column);

  GeneratedColumn<int> get ledgerId =>
      $composableBuilder(column: $table.ledgerId, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<int> get categoryId => $composableBuilder(
      column: $table.categoryId, builder: (column) => column);

  GeneratedColumn<double> get amount =>
      $composableBuilder(column: $table.amount, builder: (column) => column);

  GeneratedColumn<String> get period =>
      $composableBuilder(column: $table.period, builder: (column) => column);

  GeneratedColumn<int> get startDay =>
      $composableBuilder(column: $table.startDay, builder: (column) => column);

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$BudgetsTableTableManager extends RootTableManager<
    _$BeeDatabase,
    $BudgetsTable,
    Budget,
    $$BudgetsTableFilterComposer,
    $$BudgetsTableOrderingComposer,
    $$BudgetsTableAnnotationComposer,
    $$BudgetsTableCreateCompanionBuilder,
    $$BudgetsTableUpdateCompanionBuilder,
    (Budget, BaseReferences<_$BeeDatabase, $BudgetsTable, Budget>),
    Budget,
    PrefetchHooks Function()> {
  $$BudgetsTableTableManager(_$BeeDatabase db, $BudgetsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BudgetsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BudgetsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BudgetsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String?> syncId = const Value.absent(),
            Value<int> ledgerId = const Value.absent(),
            Value<String> type = const Value.absent(),
            Value<int?> categoryId = const Value.absent(),
            Value<double> amount = const Value.absent(),
            Value<String> period = const Value.absent(),
            Value<int> startDay = const Value.absent(),
            Value<bool> enabled = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
          }) =>
              BudgetsCompanion(
            id: id,
            syncId: syncId,
            ledgerId: ledgerId,
            type: type,
            categoryId: categoryId,
            amount: amount,
            period: period,
            startDay: startDay,
            enabled: enabled,
            createdAt: createdAt,
            updatedAt: updatedAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String?> syncId = const Value.absent(),
            required int ledgerId,
            Value<String> type = const Value.absent(),
            Value<int?> categoryId = const Value.absent(),
            required double amount,
            Value<String> period = const Value.absent(),
            Value<int> startDay = const Value.absent(),
            Value<bool> enabled = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
          }) =>
              BudgetsCompanion.insert(
            id: id,
            syncId: syncId,
            ledgerId: ledgerId,
            type: type,
            categoryId: categoryId,
            amount: amount,
            period: period,
            startDay: startDay,
            enabled: enabled,
            createdAt: createdAt,
            updatedAt: updatedAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$BudgetsTableProcessedTableManager = ProcessedTableManager<
    _$BeeDatabase,
    $BudgetsTable,
    Budget,
    $$BudgetsTableFilterComposer,
    $$BudgetsTableOrderingComposer,
    $$BudgetsTableAnnotationComposer,
    $$BudgetsTableCreateCompanionBuilder,
    $$BudgetsTableUpdateCompanionBuilder,
    (Budget, BaseReferences<_$BeeDatabase, $BudgetsTable, Budget>),
    Budget,
    PrefetchHooks Function()>;
typedef $$TransactionAttachmentsTableCreateCompanionBuilder
    = TransactionAttachmentsCompanion Function({
  Value<int> id,
  required int transactionId,
  required String fileName,
  Value<String?> originalName,
  Value<int?> fileSize,
  Value<int?> width,
  Value<int?> height,
  Value<int> sortOrder,
  Value<String?> cloudFileId,
  Value<String?> cloudSha256,
  Value<DateTime> createdAt,
});
typedef $$TransactionAttachmentsTableUpdateCompanionBuilder
    = TransactionAttachmentsCompanion Function({
  Value<int> id,
  Value<int> transactionId,
  Value<String> fileName,
  Value<String?> originalName,
  Value<int?> fileSize,
  Value<int?> width,
  Value<int?> height,
  Value<int> sortOrder,
  Value<String?> cloudFileId,
  Value<String?> cloudSha256,
  Value<DateTime> createdAt,
});

class $$TransactionAttachmentsTableFilterComposer
    extends Composer<_$BeeDatabase, $TransactionAttachmentsTable> {
  $$TransactionAttachmentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get transactionId => $composableBuilder(
      column: $table.transactionId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get fileName => $composableBuilder(
      column: $table.fileName, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get originalName => $composableBuilder(
      column: $table.originalName, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get fileSize => $composableBuilder(
      column: $table.fileSize, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get width => $composableBuilder(
      column: $table.width, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get height => $composableBuilder(
      column: $table.height, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get sortOrder => $composableBuilder(
      column: $table.sortOrder, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get cloudFileId => $composableBuilder(
      column: $table.cloudFileId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get cloudSha256 => $composableBuilder(
      column: $table.cloudSha256, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));
}

class $$TransactionAttachmentsTableOrderingComposer
    extends Composer<_$BeeDatabase, $TransactionAttachmentsTable> {
  $$TransactionAttachmentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get transactionId => $composableBuilder(
      column: $table.transactionId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get fileName => $composableBuilder(
      column: $table.fileName, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get originalName => $composableBuilder(
      column: $table.originalName,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get fileSize => $composableBuilder(
      column: $table.fileSize, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get width => $composableBuilder(
      column: $table.width, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get height => $composableBuilder(
      column: $table.height, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get sortOrder => $composableBuilder(
      column: $table.sortOrder, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get cloudFileId => $composableBuilder(
      column: $table.cloudFileId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get cloudSha256 => $composableBuilder(
      column: $table.cloudSha256, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));
}

class $$TransactionAttachmentsTableAnnotationComposer
    extends Composer<_$BeeDatabase, $TransactionAttachmentsTable> {
  $$TransactionAttachmentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get transactionId => $composableBuilder(
      column: $table.transactionId, builder: (column) => column);

  GeneratedColumn<String> get fileName =>
      $composableBuilder(column: $table.fileName, builder: (column) => column);

  GeneratedColumn<String> get originalName => $composableBuilder(
      column: $table.originalName, builder: (column) => column);

  GeneratedColumn<int> get fileSize =>
      $composableBuilder(column: $table.fileSize, builder: (column) => column);

  GeneratedColumn<int> get width =>
      $composableBuilder(column: $table.width, builder: (column) => column);

  GeneratedColumn<int> get height =>
      $composableBuilder(column: $table.height, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<String> get cloudFileId => $composableBuilder(
      column: $table.cloudFileId, builder: (column) => column);

  GeneratedColumn<String> get cloudSha256 => $composableBuilder(
      column: $table.cloudSha256, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$TransactionAttachmentsTableTableManager extends RootTableManager<
    _$BeeDatabase,
    $TransactionAttachmentsTable,
    TransactionAttachment,
    $$TransactionAttachmentsTableFilterComposer,
    $$TransactionAttachmentsTableOrderingComposer,
    $$TransactionAttachmentsTableAnnotationComposer,
    $$TransactionAttachmentsTableCreateCompanionBuilder,
    $$TransactionAttachmentsTableUpdateCompanionBuilder,
    (
      TransactionAttachment,
      BaseReferences<_$BeeDatabase, $TransactionAttachmentsTable,
          TransactionAttachment>
    ),
    TransactionAttachment,
    PrefetchHooks Function()> {
  $$TransactionAttachmentsTableTableManager(
      _$BeeDatabase db, $TransactionAttachmentsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TransactionAttachmentsTableFilterComposer(
                  $db: db, $table: table),
          createOrderingComposer: () =>
              $$TransactionAttachmentsTableOrderingComposer(
                  $db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TransactionAttachmentsTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<int> transactionId = const Value.absent(),
            Value<String> fileName = const Value.absent(),
            Value<String?> originalName = const Value.absent(),
            Value<int?> fileSize = const Value.absent(),
            Value<int?> width = const Value.absent(),
            Value<int?> height = const Value.absent(),
            Value<int> sortOrder = const Value.absent(),
            Value<String?> cloudFileId = const Value.absent(),
            Value<String?> cloudSha256 = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
          }) =>
              TransactionAttachmentsCompanion(
            id: id,
            transactionId: transactionId,
            fileName: fileName,
            originalName: originalName,
            fileSize: fileSize,
            width: width,
            height: height,
            sortOrder: sortOrder,
            cloudFileId: cloudFileId,
            cloudSha256: cloudSha256,
            createdAt: createdAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required int transactionId,
            required String fileName,
            Value<String?> originalName = const Value.absent(),
            Value<int?> fileSize = const Value.absent(),
            Value<int?> width = const Value.absent(),
            Value<int?> height = const Value.absent(),
            Value<int> sortOrder = const Value.absent(),
            Value<String?> cloudFileId = const Value.absent(),
            Value<String?> cloudSha256 = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
          }) =>
              TransactionAttachmentsCompanion.insert(
            id: id,
            transactionId: transactionId,
            fileName: fileName,
            originalName: originalName,
            fileSize: fileSize,
            width: width,
            height: height,
            sortOrder: sortOrder,
            cloudFileId: cloudFileId,
            cloudSha256: cloudSha256,
            createdAt: createdAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$TransactionAttachmentsTableProcessedTableManager
    = ProcessedTableManager<
        _$BeeDatabase,
        $TransactionAttachmentsTable,
        TransactionAttachment,
        $$TransactionAttachmentsTableFilterComposer,
        $$TransactionAttachmentsTableOrderingComposer,
        $$TransactionAttachmentsTableAnnotationComposer,
        $$TransactionAttachmentsTableCreateCompanionBuilder,
        $$TransactionAttachmentsTableUpdateCompanionBuilder,
        (
          TransactionAttachment,
          BaseReferences<_$BeeDatabase, $TransactionAttachmentsTable,
              TransactionAttachment>
        ),
        TransactionAttachment,
        PrefetchHooks Function()>;
typedef $$LocalChangesTableCreateCompanionBuilder = LocalChangesCompanion
    Function({
  Value<int> id,
  required String entityType,
  required int entityId,
  required String entitySyncId,
  required int ledgerId,
  required String action,
  Value<String?> payloadJson,
  Value<DateTime> createdAt,
  Value<DateTime?> pushedAt,
});
typedef $$LocalChangesTableUpdateCompanionBuilder = LocalChangesCompanion
    Function({
  Value<int> id,
  Value<String> entityType,
  Value<int> entityId,
  Value<String> entitySyncId,
  Value<int> ledgerId,
  Value<String> action,
  Value<String?> payloadJson,
  Value<DateTime> createdAt,
  Value<DateTime?> pushedAt,
});

class $$LocalChangesTableFilterComposer
    extends Composer<_$BeeDatabase, $LocalChangesTable> {
  $$LocalChangesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get entityType => $composableBuilder(
      column: $table.entityType, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get entityId => $composableBuilder(
      column: $table.entityId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get entitySyncId => $composableBuilder(
      column: $table.entitySyncId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get ledgerId => $composableBuilder(
      column: $table.ledgerId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get action => $composableBuilder(
      column: $table.action, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get payloadJson => $composableBuilder(
      column: $table.payloadJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get pushedAt => $composableBuilder(
      column: $table.pushedAt, builder: (column) => ColumnFilters(column));
}

class $$LocalChangesTableOrderingComposer
    extends Composer<_$BeeDatabase, $LocalChangesTable> {
  $$LocalChangesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get entityType => $composableBuilder(
      column: $table.entityType, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get entityId => $composableBuilder(
      column: $table.entityId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get entitySyncId => $composableBuilder(
      column: $table.entitySyncId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get ledgerId => $composableBuilder(
      column: $table.ledgerId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get action => $composableBuilder(
      column: $table.action, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get payloadJson => $composableBuilder(
      column: $table.payloadJson, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get pushedAt => $composableBuilder(
      column: $table.pushedAt, builder: (column) => ColumnOrderings(column));
}

class $$LocalChangesTableAnnotationComposer
    extends Composer<_$BeeDatabase, $LocalChangesTable> {
  $$LocalChangesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get entityType => $composableBuilder(
      column: $table.entityType, builder: (column) => column);

  GeneratedColumn<int> get entityId =>
      $composableBuilder(column: $table.entityId, builder: (column) => column);

  GeneratedColumn<String> get entitySyncId => $composableBuilder(
      column: $table.entitySyncId, builder: (column) => column);

  GeneratedColumn<int> get ledgerId =>
      $composableBuilder(column: $table.ledgerId, builder: (column) => column);

  GeneratedColumn<String> get action =>
      $composableBuilder(column: $table.action, builder: (column) => column);

  GeneratedColumn<String> get payloadJson => $composableBuilder(
      column: $table.payloadJson, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get pushedAt =>
      $composableBuilder(column: $table.pushedAt, builder: (column) => column);
}

class $$LocalChangesTableTableManager extends RootTableManager<
    _$BeeDatabase,
    $LocalChangesTable,
    LocalChange,
    $$LocalChangesTableFilterComposer,
    $$LocalChangesTableOrderingComposer,
    $$LocalChangesTableAnnotationComposer,
    $$LocalChangesTableCreateCompanionBuilder,
    $$LocalChangesTableUpdateCompanionBuilder,
    (
      LocalChange,
      BaseReferences<_$BeeDatabase, $LocalChangesTable, LocalChange>
    ),
    LocalChange,
    PrefetchHooks Function()> {
  $$LocalChangesTableTableManager(_$BeeDatabase db, $LocalChangesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalChangesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalChangesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalChangesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> entityType = const Value.absent(),
            Value<int> entityId = const Value.absent(),
            Value<String> entitySyncId = const Value.absent(),
            Value<int> ledgerId = const Value.absent(),
            Value<String> action = const Value.absent(),
            Value<String?> payloadJson = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime?> pushedAt = const Value.absent(),
          }) =>
              LocalChangesCompanion(
            id: id,
            entityType: entityType,
            entityId: entityId,
            entitySyncId: entitySyncId,
            ledgerId: ledgerId,
            action: action,
            payloadJson: payloadJson,
            createdAt: createdAt,
            pushedAt: pushedAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String entityType,
            required int entityId,
            required String entitySyncId,
            required int ledgerId,
            required String action,
            Value<String?> payloadJson = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime?> pushedAt = const Value.absent(),
          }) =>
              LocalChangesCompanion.insert(
            id: id,
            entityType: entityType,
            entityId: entityId,
            entitySyncId: entitySyncId,
            ledgerId: ledgerId,
            action: action,
            payloadJson: payloadJson,
            createdAt: createdAt,
            pushedAt: pushedAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$LocalChangesTableProcessedTableManager = ProcessedTableManager<
    _$BeeDatabase,
    $LocalChangesTable,
    LocalChange,
    $$LocalChangesTableFilterComposer,
    $$LocalChangesTableOrderingComposer,
    $$LocalChangesTableAnnotationComposer,
    $$LocalChangesTableCreateCompanionBuilder,
    $$LocalChangesTableUpdateCompanionBuilder,
    (
      LocalChange,
      BaseReferences<_$BeeDatabase, $LocalChangesTable, LocalChange>
    ),
    LocalChange,
    PrefetchHooks Function()>;
typedef $$SyncStateTableCreateCompanionBuilder = SyncStateCompanion Function({
  Value<int> id,
  required String deviceId,
  Value<String> providerType,
  Value<int> serverCursor,
  Value<DateTime?> lastPushAt,
  Value<DateTime?> lastPullAt,
});
typedef $$SyncStateTableUpdateCompanionBuilder = SyncStateCompanion Function({
  Value<int> id,
  Value<String> deviceId,
  Value<String> providerType,
  Value<int> serverCursor,
  Value<DateTime?> lastPushAt,
  Value<DateTime?> lastPullAt,
});

class $$SyncStateTableFilterComposer
    extends Composer<_$BeeDatabase, $SyncStateTable> {
  $$SyncStateTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get deviceId => $composableBuilder(
      column: $table.deviceId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get providerType => $composableBuilder(
      column: $table.providerType, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get serverCursor => $composableBuilder(
      column: $table.serverCursor, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get lastPushAt => $composableBuilder(
      column: $table.lastPushAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get lastPullAt => $composableBuilder(
      column: $table.lastPullAt, builder: (column) => ColumnFilters(column));
}

class $$SyncStateTableOrderingComposer
    extends Composer<_$BeeDatabase, $SyncStateTable> {
  $$SyncStateTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get deviceId => $composableBuilder(
      column: $table.deviceId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get providerType => $composableBuilder(
      column: $table.providerType,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get serverCursor => $composableBuilder(
      column: $table.serverCursor,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get lastPushAt => $composableBuilder(
      column: $table.lastPushAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get lastPullAt => $composableBuilder(
      column: $table.lastPullAt, builder: (column) => ColumnOrderings(column));
}

class $$SyncStateTableAnnotationComposer
    extends Composer<_$BeeDatabase, $SyncStateTable> {
  $$SyncStateTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get providerType => $composableBuilder(
      column: $table.providerType, builder: (column) => column);

  GeneratedColumn<int> get serverCursor => $composableBuilder(
      column: $table.serverCursor, builder: (column) => column);

  GeneratedColumn<DateTime> get lastPushAt => $composableBuilder(
      column: $table.lastPushAt, builder: (column) => column);

  GeneratedColumn<DateTime> get lastPullAt => $composableBuilder(
      column: $table.lastPullAt, builder: (column) => column);
}

class $$SyncStateTableTableManager extends RootTableManager<
    _$BeeDatabase,
    $SyncStateTable,
    SyncStateData,
    $$SyncStateTableFilterComposer,
    $$SyncStateTableOrderingComposer,
    $$SyncStateTableAnnotationComposer,
    $$SyncStateTableCreateCompanionBuilder,
    $$SyncStateTableUpdateCompanionBuilder,
    (
      SyncStateData,
      BaseReferences<_$BeeDatabase, $SyncStateTable, SyncStateData>
    ),
    SyncStateData,
    PrefetchHooks Function()> {
  $$SyncStateTableTableManager(_$BeeDatabase db, $SyncStateTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncStateTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncStateTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncStateTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> deviceId = const Value.absent(),
            Value<String> providerType = const Value.absent(),
            Value<int> serverCursor = const Value.absent(),
            Value<DateTime?> lastPushAt = const Value.absent(),
            Value<DateTime?> lastPullAt = const Value.absent(),
          }) =>
              SyncStateCompanion(
            id: id,
            deviceId: deviceId,
            providerType: providerType,
            serverCursor: serverCursor,
            lastPushAt: lastPushAt,
            lastPullAt: lastPullAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String deviceId,
            Value<String> providerType = const Value.absent(),
            Value<int> serverCursor = const Value.absent(),
            Value<DateTime?> lastPushAt = const Value.absent(),
            Value<DateTime?> lastPullAt = const Value.absent(),
          }) =>
              SyncStateCompanion.insert(
            id: id,
            deviceId: deviceId,
            providerType: providerType,
            serverCursor: serverCursor,
            lastPushAt: lastPushAt,
            lastPullAt: lastPullAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$SyncStateTableProcessedTableManager = ProcessedTableManager<
    _$BeeDatabase,
    $SyncStateTable,
    SyncStateData,
    $$SyncStateTableFilterComposer,
    $$SyncStateTableOrderingComposer,
    $$SyncStateTableAnnotationComposer,
    $$SyncStateTableCreateCompanionBuilder,
    $$SyncStateTableUpdateCompanionBuilder,
    (
      SyncStateData,
      BaseReferences<_$BeeDatabase, $SyncStateTable, SyncStateData>
    ),
    SyncStateData,
    PrefetchHooks Function()>;
typedef $$LedgerMembersTableCreateCompanionBuilder = LedgerMembersCompanion
    Function({
  required String ledgerSyncId,
  required String userId,
  Value<String?> email,
  Value<String?> displayName,
  Value<String?> avatarUrl,
  required String role,
  required DateTime joinedAt,
  required DateTime updatedAt,
  Value<int> rowid,
});
typedef $$LedgerMembersTableUpdateCompanionBuilder = LedgerMembersCompanion
    Function({
  Value<String> ledgerSyncId,
  Value<String> userId,
  Value<String?> email,
  Value<String?> displayName,
  Value<String?> avatarUrl,
  Value<String> role,
  Value<DateTime> joinedAt,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

class $$LedgerMembersTableFilterComposer
    extends Composer<_$BeeDatabase, $LedgerMembersTable> {
  $$LedgerMembersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get ledgerSyncId => $composableBuilder(
      column: $table.ledgerSyncId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get userId => $composableBuilder(
      column: $table.userId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get email => $composableBuilder(
      column: $table.email, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get displayName => $composableBuilder(
      column: $table.displayName, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get avatarUrl => $composableBuilder(
      column: $table.avatarUrl, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get role => $composableBuilder(
      column: $table.role, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get joinedAt => $composableBuilder(
      column: $table.joinedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$LedgerMembersTableOrderingComposer
    extends Composer<_$BeeDatabase, $LedgerMembersTable> {
  $$LedgerMembersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get ledgerSyncId => $composableBuilder(
      column: $table.ledgerSyncId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get userId => $composableBuilder(
      column: $table.userId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get email => $composableBuilder(
      column: $table.email, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get displayName => $composableBuilder(
      column: $table.displayName, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get avatarUrl => $composableBuilder(
      column: $table.avatarUrl, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get role => $composableBuilder(
      column: $table.role, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get joinedAt => $composableBuilder(
      column: $table.joinedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$LedgerMembersTableAnnotationComposer
    extends Composer<_$BeeDatabase, $LedgerMembersTable> {
  $$LedgerMembersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get ledgerSyncId => $composableBuilder(
      column: $table.ledgerSyncId, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get email =>
      $composableBuilder(column: $table.email, builder: (column) => column);

  GeneratedColumn<String> get displayName => $composableBuilder(
      column: $table.displayName, builder: (column) => column);

  GeneratedColumn<String> get avatarUrl =>
      $composableBuilder(column: $table.avatarUrl, builder: (column) => column);

  GeneratedColumn<String> get role =>
      $composableBuilder(column: $table.role, builder: (column) => column);

  GeneratedColumn<DateTime> get joinedAt =>
      $composableBuilder(column: $table.joinedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$LedgerMembersTableTableManager extends RootTableManager<
    _$BeeDatabase,
    $LedgerMembersTable,
    LedgerMember,
    $$LedgerMembersTableFilterComposer,
    $$LedgerMembersTableOrderingComposer,
    $$LedgerMembersTableAnnotationComposer,
    $$LedgerMembersTableCreateCompanionBuilder,
    $$LedgerMembersTableUpdateCompanionBuilder,
    (
      LedgerMember,
      BaseReferences<_$BeeDatabase, $LedgerMembersTable, LedgerMember>
    ),
    LedgerMember,
    PrefetchHooks Function()> {
  $$LedgerMembersTableTableManager(_$BeeDatabase db, $LedgerMembersTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LedgerMembersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LedgerMembersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LedgerMembersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> ledgerSyncId = const Value.absent(),
            Value<String> userId = const Value.absent(),
            Value<String?> email = const Value.absent(),
            Value<String?> displayName = const Value.absent(),
            Value<String?> avatarUrl = const Value.absent(),
            Value<String> role = const Value.absent(),
            Value<DateTime> joinedAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              LedgerMembersCompanion(
            ledgerSyncId: ledgerSyncId,
            userId: userId,
            email: email,
            displayName: displayName,
            avatarUrl: avatarUrl,
            role: role,
            joinedAt: joinedAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String ledgerSyncId,
            required String userId,
            Value<String?> email = const Value.absent(),
            Value<String?> displayName = const Value.absent(),
            Value<String?> avatarUrl = const Value.absent(),
            required String role,
            required DateTime joinedAt,
            required DateTime updatedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              LedgerMembersCompanion.insert(
            ledgerSyncId: ledgerSyncId,
            userId: userId,
            email: email,
            displayName: displayName,
            avatarUrl: avatarUrl,
            role: role,
            joinedAt: joinedAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$LedgerMembersTableProcessedTableManager = ProcessedTableManager<
    _$BeeDatabase,
    $LedgerMembersTable,
    LedgerMember,
    $$LedgerMembersTableFilterComposer,
    $$LedgerMembersTableOrderingComposer,
    $$LedgerMembersTableAnnotationComposer,
    $$LedgerMembersTableCreateCompanionBuilder,
    $$LedgerMembersTableUpdateCompanionBuilder,
    (
      LedgerMember,
      BaseReferences<_$BeeDatabase, $LedgerMembersTable, LedgerMember>
    ),
    LedgerMember,
    PrefetchHooks Function()>;
typedef $$SharedLedgerCategoriesTableCreateCompanionBuilder
    = SharedLedgerCategoriesCompanion Function({
  required String ledgerSyncId,
  required String syncId,
  required String name,
  required String kind,
  Value<String?> icon,
  Value<String> iconType,
  Value<String?> iconCloudFileId,
  Value<String?> iconCloudSha256,
  Value<String?> color,
  Value<int> sortOrder,
  Value<int> level,
  Value<String?> parentName,
  Value<String?> parentSyncId,
  required DateTime updatedAt,
  Value<int> rowid,
});
typedef $$SharedLedgerCategoriesTableUpdateCompanionBuilder
    = SharedLedgerCategoriesCompanion Function({
  Value<String> ledgerSyncId,
  Value<String> syncId,
  Value<String> name,
  Value<String> kind,
  Value<String?> icon,
  Value<String> iconType,
  Value<String?> iconCloudFileId,
  Value<String?> iconCloudSha256,
  Value<String?> color,
  Value<int> sortOrder,
  Value<int> level,
  Value<String?> parentName,
  Value<String?> parentSyncId,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

class $$SharedLedgerCategoriesTableFilterComposer
    extends Composer<_$BeeDatabase, $SharedLedgerCategoriesTable> {
  $$SharedLedgerCategoriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get ledgerSyncId => $composableBuilder(
      column: $table.ledgerSyncId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get syncId => $composableBuilder(
      column: $table.syncId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get kind => $composableBuilder(
      column: $table.kind, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get icon => $composableBuilder(
      column: $table.icon, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get iconType => $composableBuilder(
      column: $table.iconType, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get iconCloudFileId => $composableBuilder(
      column: $table.iconCloudFileId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get iconCloudSha256 => $composableBuilder(
      column: $table.iconCloudSha256,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get color => $composableBuilder(
      column: $table.color, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get sortOrder => $composableBuilder(
      column: $table.sortOrder, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get level => $composableBuilder(
      column: $table.level, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get parentName => $composableBuilder(
      column: $table.parentName, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get parentSyncId => $composableBuilder(
      column: $table.parentSyncId, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$SharedLedgerCategoriesTableOrderingComposer
    extends Composer<_$BeeDatabase, $SharedLedgerCategoriesTable> {
  $$SharedLedgerCategoriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get ledgerSyncId => $composableBuilder(
      column: $table.ledgerSyncId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get syncId => $composableBuilder(
      column: $table.syncId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get kind => $composableBuilder(
      column: $table.kind, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get icon => $composableBuilder(
      column: $table.icon, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get iconType => $composableBuilder(
      column: $table.iconType, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get iconCloudFileId => $composableBuilder(
      column: $table.iconCloudFileId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get iconCloudSha256 => $composableBuilder(
      column: $table.iconCloudSha256,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get color => $composableBuilder(
      column: $table.color, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get sortOrder => $composableBuilder(
      column: $table.sortOrder, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get level => $composableBuilder(
      column: $table.level, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get parentName => $composableBuilder(
      column: $table.parentName, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get parentSyncId => $composableBuilder(
      column: $table.parentSyncId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$SharedLedgerCategoriesTableAnnotationComposer
    extends Composer<_$BeeDatabase, $SharedLedgerCategoriesTable> {
  $$SharedLedgerCategoriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get ledgerSyncId => $composableBuilder(
      column: $table.ledgerSyncId, builder: (column) => column);

  GeneratedColumn<String> get syncId =>
      $composableBuilder(column: $table.syncId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get icon =>
      $composableBuilder(column: $table.icon, builder: (column) => column);

  GeneratedColumn<String> get iconType =>
      $composableBuilder(column: $table.iconType, builder: (column) => column);

  GeneratedColumn<String> get iconCloudFileId => $composableBuilder(
      column: $table.iconCloudFileId, builder: (column) => column);

  GeneratedColumn<String> get iconCloudSha256 => $composableBuilder(
      column: $table.iconCloudSha256, builder: (column) => column);

  GeneratedColumn<String> get color =>
      $composableBuilder(column: $table.color, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<int> get level =>
      $composableBuilder(column: $table.level, builder: (column) => column);

  GeneratedColumn<String> get parentName => $composableBuilder(
      column: $table.parentName, builder: (column) => column);

  GeneratedColumn<String> get parentSyncId => $composableBuilder(
      column: $table.parentSyncId, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$SharedLedgerCategoriesTableTableManager extends RootTableManager<
    _$BeeDatabase,
    $SharedLedgerCategoriesTable,
    SharedLedgerCategory,
    $$SharedLedgerCategoriesTableFilterComposer,
    $$SharedLedgerCategoriesTableOrderingComposer,
    $$SharedLedgerCategoriesTableAnnotationComposer,
    $$SharedLedgerCategoriesTableCreateCompanionBuilder,
    $$SharedLedgerCategoriesTableUpdateCompanionBuilder,
    (
      SharedLedgerCategory,
      BaseReferences<_$BeeDatabase, $SharedLedgerCategoriesTable,
          SharedLedgerCategory>
    ),
    SharedLedgerCategory,
    PrefetchHooks Function()> {
  $$SharedLedgerCategoriesTableTableManager(
      _$BeeDatabase db, $SharedLedgerCategoriesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SharedLedgerCategoriesTableFilterComposer(
                  $db: db, $table: table),
          createOrderingComposer: () =>
              $$SharedLedgerCategoriesTableOrderingComposer(
                  $db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SharedLedgerCategoriesTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> ledgerSyncId = const Value.absent(),
            Value<String> syncId = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String> kind = const Value.absent(),
            Value<String?> icon = const Value.absent(),
            Value<String> iconType = const Value.absent(),
            Value<String?> iconCloudFileId = const Value.absent(),
            Value<String?> iconCloudSha256 = const Value.absent(),
            Value<String?> color = const Value.absent(),
            Value<int> sortOrder = const Value.absent(),
            Value<int> level = const Value.absent(),
            Value<String?> parentName = const Value.absent(),
            Value<String?> parentSyncId = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              SharedLedgerCategoriesCompanion(
            ledgerSyncId: ledgerSyncId,
            syncId: syncId,
            name: name,
            kind: kind,
            icon: icon,
            iconType: iconType,
            iconCloudFileId: iconCloudFileId,
            iconCloudSha256: iconCloudSha256,
            color: color,
            sortOrder: sortOrder,
            level: level,
            parentName: parentName,
            parentSyncId: parentSyncId,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String ledgerSyncId,
            required String syncId,
            required String name,
            required String kind,
            Value<String?> icon = const Value.absent(),
            Value<String> iconType = const Value.absent(),
            Value<String?> iconCloudFileId = const Value.absent(),
            Value<String?> iconCloudSha256 = const Value.absent(),
            Value<String?> color = const Value.absent(),
            Value<int> sortOrder = const Value.absent(),
            Value<int> level = const Value.absent(),
            Value<String?> parentName = const Value.absent(),
            Value<String?> parentSyncId = const Value.absent(),
            required DateTime updatedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              SharedLedgerCategoriesCompanion.insert(
            ledgerSyncId: ledgerSyncId,
            syncId: syncId,
            name: name,
            kind: kind,
            icon: icon,
            iconType: iconType,
            iconCloudFileId: iconCloudFileId,
            iconCloudSha256: iconCloudSha256,
            color: color,
            sortOrder: sortOrder,
            level: level,
            parentName: parentName,
            parentSyncId: parentSyncId,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$SharedLedgerCategoriesTableProcessedTableManager
    = ProcessedTableManager<
        _$BeeDatabase,
        $SharedLedgerCategoriesTable,
        SharedLedgerCategory,
        $$SharedLedgerCategoriesTableFilterComposer,
        $$SharedLedgerCategoriesTableOrderingComposer,
        $$SharedLedgerCategoriesTableAnnotationComposer,
        $$SharedLedgerCategoriesTableCreateCompanionBuilder,
        $$SharedLedgerCategoriesTableUpdateCompanionBuilder,
        (
          SharedLedgerCategory,
          BaseReferences<_$BeeDatabase, $SharedLedgerCategoriesTable,
              SharedLedgerCategory>
        ),
        SharedLedgerCategory,
        PrefetchHooks Function()>;
typedef $$SharedLedgerAccountsTableCreateCompanionBuilder
    = SharedLedgerAccountsCompanion Function({
  required String ledgerSyncId,
  required String syncId,
  required String name,
  Value<String> accountType,
  Value<String> currency,
  Value<String?> note,
  Value<double?> initialBalance,
  Value<double?> creditLimit,
  Value<int?> billingDay,
  Value<int?> paymentDueDay,
  Value<String?> bankName,
  Value<String?> cardLastFour,
  required DateTime updatedAt,
  Value<int> rowid,
});
typedef $$SharedLedgerAccountsTableUpdateCompanionBuilder
    = SharedLedgerAccountsCompanion Function({
  Value<String> ledgerSyncId,
  Value<String> syncId,
  Value<String> name,
  Value<String> accountType,
  Value<String> currency,
  Value<String?> note,
  Value<double?> initialBalance,
  Value<double?> creditLimit,
  Value<int?> billingDay,
  Value<int?> paymentDueDay,
  Value<String?> bankName,
  Value<String?> cardLastFour,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

class $$SharedLedgerAccountsTableFilterComposer
    extends Composer<_$BeeDatabase, $SharedLedgerAccountsTable> {
  $$SharedLedgerAccountsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get ledgerSyncId => $composableBuilder(
      column: $table.ledgerSyncId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get syncId => $composableBuilder(
      column: $table.syncId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get accountType => $composableBuilder(
      column: $table.accountType, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get currency => $composableBuilder(
      column: $table.currency, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get note => $composableBuilder(
      column: $table.note, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get initialBalance => $composableBuilder(
      column: $table.initialBalance,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get creditLimit => $composableBuilder(
      column: $table.creditLimit, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get billingDay => $composableBuilder(
      column: $table.billingDay, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get paymentDueDay => $composableBuilder(
      column: $table.paymentDueDay, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get bankName => $composableBuilder(
      column: $table.bankName, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get cardLastFour => $composableBuilder(
      column: $table.cardLastFour, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$SharedLedgerAccountsTableOrderingComposer
    extends Composer<_$BeeDatabase, $SharedLedgerAccountsTable> {
  $$SharedLedgerAccountsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get ledgerSyncId => $composableBuilder(
      column: $table.ledgerSyncId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get syncId => $composableBuilder(
      column: $table.syncId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get accountType => $composableBuilder(
      column: $table.accountType, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get currency => $composableBuilder(
      column: $table.currency, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get note => $composableBuilder(
      column: $table.note, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get initialBalance => $composableBuilder(
      column: $table.initialBalance,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get creditLimit => $composableBuilder(
      column: $table.creditLimit, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get billingDay => $composableBuilder(
      column: $table.billingDay, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get paymentDueDay => $composableBuilder(
      column: $table.paymentDueDay,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get bankName => $composableBuilder(
      column: $table.bankName, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get cardLastFour => $composableBuilder(
      column: $table.cardLastFour,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$SharedLedgerAccountsTableAnnotationComposer
    extends Composer<_$BeeDatabase, $SharedLedgerAccountsTable> {
  $$SharedLedgerAccountsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get ledgerSyncId => $composableBuilder(
      column: $table.ledgerSyncId, builder: (column) => column);

  GeneratedColumn<String> get syncId =>
      $composableBuilder(column: $table.syncId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get accountType => $composableBuilder(
      column: $table.accountType, builder: (column) => column);

  GeneratedColumn<String> get currency =>
      $composableBuilder(column: $table.currency, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<double> get initialBalance => $composableBuilder(
      column: $table.initialBalance, builder: (column) => column);

  GeneratedColumn<double> get creditLimit => $composableBuilder(
      column: $table.creditLimit, builder: (column) => column);

  GeneratedColumn<int> get billingDay => $composableBuilder(
      column: $table.billingDay, builder: (column) => column);

  GeneratedColumn<int> get paymentDueDay => $composableBuilder(
      column: $table.paymentDueDay, builder: (column) => column);

  GeneratedColumn<String> get bankName =>
      $composableBuilder(column: $table.bankName, builder: (column) => column);

  GeneratedColumn<String> get cardLastFour => $composableBuilder(
      column: $table.cardLastFour, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$SharedLedgerAccountsTableTableManager extends RootTableManager<
    _$BeeDatabase,
    $SharedLedgerAccountsTable,
    SharedLedgerAccount,
    $$SharedLedgerAccountsTableFilterComposer,
    $$SharedLedgerAccountsTableOrderingComposer,
    $$SharedLedgerAccountsTableAnnotationComposer,
    $$SharedLedgerAccountsTableCreateCompanionBuilder,
    $$SharedLedgerAccountsTableUpdateCompanionBuilder,
    (
      SharedLedgerAccount,
      BaseReferences<_$BeeDatabase, $SharedLedgerAccountsTable,
          SharedLedgerAccount>
    ),
    SharedLedgerAccount,
    PrefetchHooks Function()> {
  $$SharedLedgerAccountsTableTableManager(
      _$BeeDatabase db, $SharedLedgerAccountsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SharedLedgerAccountsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SharedLedgerAccountsTableOrderingComposer(
                  $db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SharedLedgerAccountsTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> ledgerSyncId = const Value.absent(),
            Value<String> syncId = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String> accountType = const Value.absent(),
            Value<String> currency = const Value.absent(),
            Value<String?> note = const Value.absent(),
            Value<double?> initialBalance = const Value.absent(),
            Value<double?> creditLimit = const Value.absent(),
            Value<int?> billingDay = const Value.absent(),
            Value<int?> paymentDueDay = const Value.absent(),
            Value<String?> bankName = const Value.absent(),
            Value<String?> cardLastFour = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              SharedLedgerAccountsCompanion(
            ledgerSyncId: ledgerSyncId,
            syncId: syncId,
            name: name,
            accountType: accountType,
            currency: currency,
            note: note,
            initialBalance: initialBalance,
            creditLimit: creditLimit,
            billingDay: billingDay,
            paymentDueDay: paymentDueDay,
            bankName: bankName,
            cardLastFour: cardLastFour,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String ledgerSyncId,
            required String syncId,
            required String name,
            Value<String> accountType = const Value.absent(),
            Value<String> currency = const Value.absent(),
            Value<String?> note = const Value.absent(),
            Value<double?> initialBalance = const Value.absent(),
            Value<double?> creditLimit = const Value.absent(),
            Value<int?> billingDay = const Value.absent(),
            Value<int?> paymentDueDay = const Value.absent(),
            Value<String?> bankName = const Value.absent(),
            Value<String?> cardLastFour = const Value.absent(),
            required DateTime updatedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              SharedLedgerAccountsCompanion.insert(
            ledgerSyncId: ledgerSyncId,
            syncId: syncId,
            name: name,
            accountType: accountType,
            currency: currency,
            note: note,
            initialBalance: initialBalance,
            creditLimit: creditLimit,
            billingDay: billingDay,
            paymentDueDay: paymentDueDay,
            bankName: bankName,
            cardLastFour: cardLastFour,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$SharedLedgerAccountsTableProcessedTableManager
    = ProcessedTableManager<
        _$BeeDatabase,
        $SharedLedgerAccountsTable,
        SharedLedgerAccount,
        $$SharedLedgerAccountsTableFilterComposer,
        $$SharedLedgerAccountsTableOrderingComposer,
        $$SharedLedgerAccountsTableAnnotationComposer,
        $$SharedLedgerAccountsTableCreateCompanionBuilder,
        $$SharedLedgerAccountsTableUpdateCompanionBuilder,
        (
          SharedLedgerAccount,
          BaseReferences<_$BeeDatabase, $SharedLedgerAccountsTable,
              SharedLedgerAccount>
        ),
        SharedLedgerAccount,
        PrefetchHooks Function()>;
typedef $$SharedLedgerTagsTableCreateCompanionBuilder
    = SharedLedgerTagsCompanion Function({
  required String ledgerSyncId,
  required String syncId,
  required String name,
  Value<String?> color,
  required DateTime updatedAt,
  Value<int> rowid,
});
typedef $$SharedLedgerTagsTableUpdateCompanionBuilder
    = SharedLedgerTagsCompanion Function({
  Value<String> ledgerSyncId,
  Value<String> syncId,
  Value<String> name,
  Value<String?> color,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

class $$SharedLedgerTagsTableFilterComposer
    extends Composer<_$BeeDatabase, $SharedLedgerTagsTable> {
  $$SharedLedgerTagsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get ledgerSyncId => $composableBuilder(
      column: $table.ledgerSyncId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get syncId => $composableBuilder(
      column: $table.syncId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get color => $composableBuilder(
      column: $table.color, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$SharedLedgerTagsTableOrderingComposer
    extends Composer<_$BeeDatabase, $SharedLedgerTagsTable> {
  $$SharedLedgerTagsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get ledgerSyncId => $composableBuilder(
      column: $table.ledgerSyncId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get syncId => $composableBuilder(
      column: $table.syncId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get color => $composableBuilder(
      column: $table.color, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$SharedLedgerTagsTableAnnotationComposer
    extends Composer<_$BeeDatabase, $SharedLedgerTagsTable> {
  $$SharedLedgerTagsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get ledgerSyncId => $composableBuilder(
      column: $table.ledgerSyncId, builder: (column) => column);

  GeneratedColumn<String> get syncId =>
      $composableBuilder(column: $table.syncId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get color =>
      $composableBuilder(column: $table.color, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$SharedLedgerTagsTableTableManager extends RootTableManager<
    _$BeeDatabase,
    $SharedLedgerTagsTable,
    SharedLedgerTag,
    $$SharedLedgerTagsTableFilterComposer,
    $$SharedLedgerTagsTableOrderingComposer,
    $$SharedLedgerTagsTableAnnotationComposer,
    $$SharedLedgerTagsTableCreateCompanionBuilder,
    $$SharedLedgerTagsTableUpdateCompanionBuilder,
    (
      SharedLedgerTag,
      BaseReferences<_$BeeDatabase, $SharedLedgerTagsTable, SharedLedgerTag>
    ),
    SharedLedgerTag,
    PrefetchHooks Function()> {
  $$SharedLedgerTagsTableTableManager(
      _$BeeDatabase db, $SharedLedgerTagsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SharedLedgerTagsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SharedLedgerTagsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SharedLedgerTagsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> ledgerSyncId = const Value.absent(),
            Value<String> syncId = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String?> color = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              SharedLedgerTagsCompanion(
            ledgerSyncId: ledgerSyncId,
            syncId: syncId,
            name: name,
            color: color,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String ledgerSyncId,
            required String syncId,
            required String name,
            Value<String?> color = const Value.absent(),
            required DateTime updatedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              SharedLedgerTagsCompanion.insert(
            ledgerSyncId: ledgerSyncId,
            syncId: syncId,
            name: name,
            color: color,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$SharedLedgerTagsTableProcessedTableManager = ProcessedTableManager<
    _$BeeDatabase,
    $SharedLedgerTagsTable,
    SharedLedgerTag,
    $$SharedLedgerTagsTableFilterComposer,
    $$SharedLedgerTagsTableOrderingComposer,
    $$SharedLedgerTagsTableAnnotationComposer,
    $$SharedLedgerTagsTableCreateCompanionBuilder,
    $$SharedLedgerTagsTableUpdateCompanionBuilder,
    (
      SharedLedgerTag,
      BaseReferences<_$BeeDatabase, $SharedLedgerTagsTable, SharedLedgerTag>
    ),
    SharedLedgerTag,
    PrefetchHooks Function()>;
typedef $$TransactionTagOverridesTableCreateCompanionBuilder
    = TransactionTagOverridesCompanion Function({
  required String transactionSyncId,
  required String tagSyncId,
  required DateTime createdAt,
  Value<int> rowid,
});
typedef $$TransactionTagOverridesTableUpdateCompanionBuilder
    = TransactionTagOverridesCompanion Function({
  Value<String> transactionSyncId,
  Value<String> tagSyncId,
  Value<DateTime> createdAt,
  Value<int> rowid,
});

class $$TransactionTagOverridesTableFilterComposer
    extends Composer<_$BeeDatabase, $TransactionTagOverridesTable> {
  $$TransactionTagOverridesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get transactionSyncId => $composableBuilder(
      column: $table.transactionSyncId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get tagSyncId => $composableBuilder(
      column: $table.tagSyncId, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));
}

class $$TransactionTagOverridesTableOrderingComposer
    extends Composer<_$BeeDatabase, $TransactionTagOverridesTable> {
  $$TransactionTagOverridesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get transactionSyncId => $composableBuilder(
      column: $table.transactionSyncId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get tagSyncId => $composableBuilder(
      column: $table.tagSyncId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));
}

class $$TransactionTagOverridesTableAnnotationComposer
    extends Composer<_$BeeDatabase, $TransactionTagOverridesTable> {
  $$TransactionTagOverridesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get transactionSyncId => $composableBuilder(
      column: $table.transactionSyncId, builder: (column) => column);

  GeneratedColumn<String> get tagSyncId =>
      $composableBuilder(column: $table.tagSyncId, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$TransactionTagOverridesTableTableManager extends RootTableManager<
    _$BeeDatabase,
    $TransactionTagOverridesTable,
    TransactionTagOverride,
    $$TransactionTagOverridesTableFilterComposer,
    $$TransactionTagOverridesTableOrderingComposer,
    $$TransactionTagOverridesTableAnnotationComposer,
    $$TransactionTagOverridesTableCreateCompanionBuilder,
    $$TransactionTagOverridesTableUpdateCompanionBuilder,
    (
      TransactionTagOverride,
      BaseReferences<_$BeeDatabase, $TransactionTagOverridesTable,
          TransactionTagOverride>
    ),
    TransactionTagOverride,
    PrefetchHooks Function()> {
  $$TransactionTagOverridesTableTableManager(
      _$BeeDatabase db, $TransactionTagOverridesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TransactionTagOverridesTableFilterComposer(
                  $db: db, $table: table),
          createOrderingComposer: () =>
              $$TransactionTagOverridesTableOrderingComposer(
                  $db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TransactionTagOverridesTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> transactionSyncId = const Value.absent(),
            Value<String> tagSyncId = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              TransactionTagOverridesCompanion(
            transactionSyncId: transactionSyncId,
            tagSyncId: tagSyncId,
            createdAt: createdAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String transactionSyncId,
            required String tagSyncId,
            required DateTime createdAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              TransactionTagOverridesCompanion.insert(
            transactionSyncId: transactionSyncId,
            tagSyncId: tagSyncId,
            createdAt: createdAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$TransactionTagOverridesTableProcessedTableManager
    = ProcessedTableManager<
        _$BeeDatabase,
        $TransactionTagOverridesTable,
        TransactionTagOverride,
        $$TransactionTagOverridesTableFilterComposer,
        $$TransactionTagOverridesTableOrderingComposer,
        $$TransactionTagOverridesTableAnnotationComposer,
        $$TransactionTagOverridesTableCreateCompanionBuilder,
        $$TransactionTagOverridesTableUpdateCompanionBuilder,
        (
          TransactionTagOverride,
          BaseReferences<_$BeeDatabase, $TransactionTagOverridesTable,
              TransactionTagOverride>
        ),
        TransactionTagOverride,
        PrefetchHooks Function()>;
typedef $$SyncPullErrorsTableCreateCompanionBuilder = SyncPullErrorsCompanion
    Function({
  Value<int> id,
  required int changeId,
  Value<String?> ledgerExternalId,
  required String entityType,
  required String entitySyncId,
  required String action,
  required String rawChangeJson,
  Value<String?> errorClass,
  Value<String?> errorMessage,
  Value<String?> stackTrace,
  required DateTime firstSeenAt,
  required DateTime lastAttemptAt,
  Value<int> attemptCount,
  Value<String?> userAction,
  Value<DateTime?> resolvedAt,
});
typedef $$SyncPullErrorsTableUpdateCompanionBuilder = SyncPullErrorsCompanion
    Function({
  Value<int> id,
  Value<int> changeId,
  Value<String?> ledgerExternalId,
  Value<String> entityType,
  Value<String> entitySyncId,
  Value<String> action,
  Value<String> rawChangeJson,
  Value<String?> errorClass,
  Value<String?> errorMessage,
  Value<String?> stackTrace,
  Value<DateTime> firstSeenAt,
  Value<DateTime> lastAttemptAt,
  Value<int> attemptCount,
  Value<String?> userAction,
  Value<DateTime?> resolvedAt,
});

class $$SyncPullErrorsTableFilterComposer
    extends Composer<_$BeeDatabase, $SyncPullErrorsTable> {
  $$SyncPullErrorsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get changeId => $composableBuilder(
      column: $table.changeId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get ledgerExternalId => $composableBuilder(
      column: $table.ledgerExternalId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get entityType => $composableBuilder(
      column: $table.entityType, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get entitySyncId => $composableBuilder(
      column: $table.entitySyncId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get action => $composableBuilder(
      column: $table.action, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get rawChangeJson => $composableBuilder(
      column: $table.rawChangeJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get errorClass => $composableBuilder(
      column: $table.errorClass, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get errorMessage => $composableBuilder(
      column: $table.errorMessage, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get stackTrace => $composableBuilder(
      column: $table.stackTrace, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get firstSeenAt => $composableBuilder(
      column: $table.firstSeenAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get lastAttemptAt => $composableBuilder(
      column: $table.lastAttemptAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get attemptCount => $composableBuilder(
      column: $table.attemptCount, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get userAction => $composableBuilder(
      column: $table.userAction, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get resolvedAt => $composableBuilder(
      column: $table.resolvedAt, builder: (column) => ColumnFilters(column));
}

class $$SyncPullErrorsTableOrderingComposer
    extends Composer<_$BeeDatabase, $SyncPullErrorsTable> {
  $$SyncPullErrorsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get changeId => $composableBuilder(
      column: $table.changeId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get ledgerExternalId => $composableBuilder(
      column: $table.ledgerExternalId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get entityType => $composableBuilder(
      column: $table.entityType, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get entitySyncId => $composableBuilder(
      column: $table.entitySyncId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get action => $composableBuilder(
      column: $table.action, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get rawChangeJson => $composableBuilder(
      column: $table.rawChangeJson,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get errorClass => $composableBuilder(
      column: $table.errorClass, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get errorMessage => $composableBuilder(
      column: $table.errorMessage,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get stackTrace => $composableBuilder(
      column: $table.stackTrace, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get firstSeenAt => $composableBuilder(
      column: $table.firstSeenAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get lastAttemptAt => $composableBuilder(
      column: $table.lastAttemptAt,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get attemptCount => $composableBuilder(
      column: $table.attemptCount,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get userAction => $composableBuilder(
      column: $table.userAction, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get resolvedAt => $composableBuilder(
      column: $table.resolvedAt, builder: (column) => ColumnOrderings(column));
}

class $$SyncPullErrorsTableAnnotationComposer
    extends Composer<_$BeeDatabase, $SyncPullErrorsTable> {
  $$SyncPullErrorsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get changeId =>
      $composableBuilder(column: $table.changeId, builder: (column) => column);

  GeneratedColumn<String> get ledgerExternalId => $composableBuilder(
      column: $table.ledgerExternalId, builder: (column) => column);

  GeneratedColumn<String> get entityType => $composableBuilder(
      column: $table.entityType, builder: (column) => column);

  GeneratedColumn<String> get entitySyncId => $composableBuilder(
      column: $table.entitySyncId, builder: (column) => column);

  GeneratedColumn<String> get action =>
      $composableBuilder(column: $table.action, builder: (column) => column);

  GeneratedColumn<String> get rawChangeJson => $composableBuilder(
      column: $table.rawChangeJson, builder: (column) => column);

  GeneratedColumn<String> get errorClass => $composableBuilder(
      column: $table.errorClass, builder: (column) => column);

  GeneratedColumn<String> get errorMessage => $composableBuilder(
      column: $table.errorMessage, builder: (column) => column);

  GeneratedColumn<String> get stackTrace => $composableBuilder(
      column: $table.stackTrace, builder: (column) => column);

  GeneratedColumn<DateTime> get firstSeenAt => $composableBuilder(
      column: $table.firstSeenAt, builder: (column) => column);

  GeneratedColumn<DateTime> get lastAttemptAt => $composableBuilder(
      column: $table.lastAttemptAt, builder: (column) => column);

  GeneratedColumn<int> get attemptCount => $composableBuilder(
      column: $table.attemptCount, builder: (column) => column);

  GeneratedColumn<String> get userAction => $composableBuilder(
      column: $table.userAction, builder: (column) => column);

  GeneratedColumn<DateTime> get resolvedAt => $composableBuilder(
      column: $table.resolvedAt, builder: (column) => column);
}

class $$SyncPullErrorsTableTableManager extends RootTableManager<
    _$BeeDatabase,
    $SyncPullErrorsTable,
    SyncPullError,
    $$SyncPullErrorsTableFilterComposer,
    $$SyncPullErrorsTableOrderingComposer,
    $$SyncPullErrorsTableAnnotationComposer,
    $$SyncPullErrorsTableCreateCompanionBuilder,
    $$SyncPullErrorsTableUpdateCompanionBuilder,
    (
      SyncPullError,
      BaseReferences<_$BeeDatabase, $SyncPullErrorsTable, SyncPullError>
    ),
    SyncPullError,
    PrefetchHooks Function()> {
  $$SyncPullErrorsTableTableManager(
      _$BeeDatabase db, $SyncPullErrorsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncPullErrorsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncPullErrorsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncPullErrorsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<int> changeId = const Value.absent(),
            Value<String?> ledgerExternalId = const Value.absent(),
            Value<String> entityType = const Value.absent(),
            Value<String> entitySyncId = const Value.absent(),
            Value<String> action = const Value.absent(),
            Value<String> rawChangeJson = const Value.absent(),
            Value<String?> errorClass = const Value.absent(),
            Value<String?> errorMessage = const Value.absent(),
            Value<String?> stackTrace = const Value.absent(),
            Value<DateTime> firstSeenAt = const Value.absent(),
            Value<DateTime> lastAttemptAt = const Value.absent(),
            Value<int> attemptCount = const Value.absent(),
            Value<String?> userAction = const Value.absent(),
            Value<DateTime?> resolvedAt = const Value.absent(),
          }) =>
              SyncPullErrorsCompanion(
            id: id,
            changeId: changeId,
            ledgerExternalId: ledgerExternalId,
            entityType: entityType,
            entitySyncId: entitySyncId,
            action: action,
            rawChangeJson: rawChangeJson,
            errorClass: errorClass,
            errorMessage: errorMessage,
            stackTrace: stackTrace,
            firstSeenAt: firstSeenAt,
            lastAttemptAt: lastAttemptAt,
            attemptCount: attemptCount,
            userAction: userAction,
            resolvedAt: resolvedAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required int changeId,
            Value<String?> ledgerExternalId = const Value.absent(),
            required String entityType,
            required String entitySyncId,
            required String action,
            required String rawChangeJson,
            Value<String?> errorClass = const Value.absent(),
            Value<String?> errorMessage = const Value.absent(),
            Value<String?> stackTrace = const Value.absent(),
            required DateTime firstSeenAt,
            required DateTime lastAttemptAt,
            Value<int> attemptCount = const Value.absent(),
            Value<String?> userAction = const Value.absent(),
            Value<DateTime?> resolvedAt = const Value.absent(),
          }) =>
              SyncPullErrorsCompanion.insert(
            id: id,
            changeId: changeId,
            ledgerExternalId: ledgerExternalId,
            entityType: entityType,
            entitySyncId: entitySyncId,
            action: action,
            rawChangeJson: rawChangeJson,
            errorClass: errorClass,
            errorMessage: errorMessage,
            stackTrace: stackTrace,
            firstSeenAt: firstSeenAt,
            lastAttemptAt: lastAttemptAt,
            attemptCount: attemptCount,
            userAction: userAction,
            resolvedAt: resolvedAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$SyncPullErrorsTableProcessedTableManager = ProcessedTableManager<
    _$BeeDatabase,
    $SyncPullErrorsTable,
    SyncPullError,
    $$SyncPullErrorsTableFilterComposer,
    $$SyncPullErrorsTableOrderingComposer,
    $$SyncPullErrorsTableAnnotationComposer,
    $$SyncPullErrorsTableCreateCompanionBuilder,
    $$SyncPullErrorsTableUpdateCompanionBuilder,
    (
      SyncPullError,
      BaseReferences<_$BeeDatabase, $SyncPullErrorsTable, SyncPullError>
    ),
    SyncPullError,
    PrefetchHooks Function()>;
typedef $$ExchangeRatesTableCreateCompanionBuilder = ExchangeRatesCompanion
    Function({
  required String baseCurrency,
  required String quoteCurrency,
  required String rateDate,
  required String rate,
  required String source,
  required DateTime fetchedAt,
  Value<int> rowid,
});
typedef $$ExchangeRatesTableUpdateCompanionBuilder = ExchangeRatesCompanion
    Function({
  Value<String> baseCurrency,
  Value<String> quoteCurrency,
  Value<String> rateDate,
  Value<String> rate,
  Value<String> source,
  Value<DateTime> fetchedAt,
  Value<int> rowid,
});

class $$ExchangeRatesTableFilterComposer
    extends Composer<_$BeeDatabase, $ExchangeRatesTable> {
  $$ExchangeRatesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get baseCurrency => $composableBuilder(
      column: $table.baseCurrency, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get quoteCurrency => $composableBuilder(
      column: $table.quoteCurrency, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get rateDate => $composableBuilder(
      column: $table.rateDate, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get rate => $composableBuilder(
      column: $table.rate, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get source => $composableBuilder(
      column: $table.source, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get fetchedAt => $composableBuilder(
      column: $table.fetchedAt, builder: (column) => ColumnFilters(column));
}

class $$ExchangeRatesTableOrderingComposer
    extends Composer<_$BeeDatabase, $ExchangeRatesTable> {
  $$ExchangeRatesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get baseCurrency => $composableBuilder(
      column: $table.baseCurrency,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get quoteCurrency => $composableBuilder(
      column: $table.quoteCurrency,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get rateDate => $composableBuilder(
      column: $table.rateDate, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get rate => $composableBuilder(
      column: $table.rate, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get source => $composableBuilder(
      column: $table.source, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get fetchedAt => $composableBuilder(
      column: $table.fetchedAt, builder: (column) => ColumnOrderings(column));
}

class $$ExchangeRatesTableAnnotationComposer
    extends Composer<_$BeeDatabase, $ExchangeRatesTable> {
  $$ExchangeRatesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get baseCurrency => $composableBuilder(
      column: $table.baseCurrency, builder: (column) => column);

  GeneratedColumn<String> get quoteCurrency => $composableBuilder(
      column: $table.quoteCurrency, builder: (column) => column);

  GeneratedColumn<String> get rateDate =>
      $composableBuilder(column: $table.rateDate, builder: (column) => column);

  GeneratedColumn<String> get rate =>
      $composableBuilder(column: $table.rate, builder: (column) => column);

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<DateTime> get fetchedAt =>
      $composableBuilder(column: $table.fetchedAt, builder: (column) => column);
}

class $$ExchangeRatesTableTableManager extends RootTableManager<
    _$BeeDatabase,
    $ExchangeRatesTable,
    ExchangeRate,
    $$ExchangeRatesTableFilterComposer,
    $$ExchangeRatesTableOrderingComposer,
    $$ExchangeRatesTableAnnotationComposer,
    $$ExchangeRatesTableCreateCompanionBuilder,
    $$ExchangeRatesTableUpdateCompanionBuilder,
    (
      ExchangeRate,
      BaseReferences<_$BeeDatabase, $ExchangeRatesTable, ExchangeRate>
    ),
    ExchangeRate,
    PrefetchHooks Function()> {
  $$ExchangeRatesTableTableManager(_$BeeDatabase db, $ExchangeRatesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ExchangeRatesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ExchangeRatesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ExchangeRatesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> baseCurrency = const Value.absent(),
            Value<String> quoteCurrency = const Value.absent(),
            Value<String> rateDate = const Value.absent(),
            Value<String> rate = const Value.absent(),
            Value<String> source = const Value.absent(),
            Value<DateTime> fetchedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ExchangeRatesCompanion(
            baseCurrency: baseCurrency,
            quoteCurrency: quoteCurrency,
            rateDate: rateDate,
            rate: rate,
            source: source,
            fetchedAt: fetchedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String baseCurrency,
            required String quoteCurrency,
            required String rateDate,
            required String rate,
            required String source,
            required DateTime fetchedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              ExchangeRatesCompanion.insert(
            baseCurrency: baseCurrency,
            quoteCurrency: quoteCurrency,
            rateDate: rateDate,
            rate: rate,
            source: source,
            fetchedAt: fetchedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$ExchangeRatesTableProcessedTableManager = ProcessedTableManager<
    _$BeeDatabase,
    $ExchangeRatesTable,
    ExchangeRate,
    $$ExchangeRatesTableFilterComposer,
    $$ExchangeRatesTableOrderingComposer,
    $$ExchangeRatesTableAnnotationComposer,
    $$ExchangeRatesTableCreateCompanionBuilder,
    $$ExchangeRatesTableUpdateCompanionBuilder,
    (
      ExchangeRate,
      BaseReferences<_$BeeDatabase, $ExchangeRatesTable, ExchangeRate>
    ),
    ExchangeRate,
    PrefetchHooks Function()>;
typedef $$ExchangeRateOverridesTableCreateCompanionBuilder
    = ExchangeRateOverridesCompanion Function({
  Value<int> id,
  Value<String?> syncId,
  required String baseCurrency,
  required String quoteCurrency,
  required String rate,
  Value<DateTime?> updatedAt,
});
typedef $$ExchangeRateOverridesTableUpdateCompanionBuilder
    = ExchangeRateOverridesCompanion Function({
  Value<int> id,
  Value<String?> syncId,
  Value<String> baseCurrency,
  Value<String> quoteCurrency,
  Value<String> rate,
  Value<DateTime?> updatedAt,
});

class $$ExchangeRateOverridesTableFilterComposer
    extends Composer<_$BeeDatabase, $ExchangeRateOverridesTable> {
  $$ExchangeRateOverridesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get syncId => $composableBuilder(
      column: $table.syncId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get baseCurrency => $composableBuilder(
      column: $table.baseCurrency, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get quoteCurrency => $composableBuilder(
      column: $table.quoteCurrency, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get rate => $composableBuilder(
      column: $table.rate, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$ExchangeRateOverridesTableOrderingComposer
    extends Composer<_$BeeDatabase, $ExchangeRateOverridesTable> {
  $$ExchangeRateOverridesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get syncId => $composableBuilder(
      column: $table.syncId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get baseCurrency => $composableBuilder(
      column: $table.baseCurrency,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get quoteCurrency => $composableBuilder(
      column: $table.quoteCurrency,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get rate => $composableBuilder(
      column: $table.rate, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$ExchangeRateOverridesTableAnnotationComposer
    extends Composer<_$BeeDatabase, $ExchangeRateOverridesTable> {
  $$ExchangeRateOverridesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get syncId =>
      $composableBuilder(column: $table.syncId, builder: (column) => column);

  GeneratedColumn<String> get baseCurrency => $composableBuilder(
      column: $table.baseCurrency, builder: (column) => column);

  GeneratedColumn<String> get quoteCurrency => $composableBuilder(
      column: $table.quoteCurrency, builder: (column) => column);

  GeneratedColumn<String> get rate =>
      $composableBuilder(column: $table.rate, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$ExchangeRateOverridesTableTableManager extends RootTableManager<
    _$BeeDatabase,
    $ExchangeRateOverridesTable,
    ExchangeRateOverride,
    $$ExchangeRateOverridesTableFilterComposer,
    $$ExchangeRateOverridesTableOrderingComposer,
    $$ExchangeRateOverridesTableAnnotationComposer,
    $$ExchangeRateOverridesTableCreateCompanionBuilder,
    $$ExchangeRateOverridesTableUpdateCompanionBuilder,
    (
      ExchangeRateOverride,
      BaseReferences<_$BeeDatabase, $ExchangeRateOverridesTable,
          ExchangeRateOverride>
    ),
    ExchangeRateOverride,
    PrefetchHooks Function()> {
  $$ExchangeRateOverridesTableTableManager(
      _$BeeDatabase db, $ExchangeRateOverridesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ExchangeRateOverridesTableFilterComposer(
                  $db: db, $table: table),
          createOrderingComposer: () =>
              $$ExchangeRateOverridesTableOrderingComposer(
                  $db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ExchangeRateOverridesTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String?> syncId = const Value.absent(),
            Value<String> baseCurrency = const Value.absent(),
            Value<String> quoteCurrency = const Value.absent(),
            Value<String> rate = const Value.absent(),
            Value<DateTime?> updatedAt = const Value.absent(),
          }) =>
              ExchangeRateOverridesCompanion(
            id: id,
            syncId: syncId,
            baseCurrency: baseCurrency,
            quoteCurrency: quoteCurrency,
            rate: rate,
            updatedAt: updatedAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String?> syncId = const Value.absent(),
            required String baseCurrency,
            required String quoteCurrency,
            required String rate,
            Value<DateTime?> updatedAt = const Value.absent(),
          }) =>
              ExchangeRateOverridesCompanion.insert(
            id: id,
            syncId: syncId,
            baseCurrency: baseCurrency,
            quoteCurrency: quoteCurrency,
            rate: rate,
            updatedAt: updatedAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$ExchangeRateOverridesTableProcessedTableManager
    = ProcessedTableManager<
        _$BeeDatabase,
        $ExchangeRateOverridesTable,
        ExchangeRateOverride,
        $$ExchangeRateOverridesTableFilterComposer,
        $$ExchangeRateOverridesTableOrderingComposer,
        $$ExchangeRateOverridesTableAnnotationComposer,
        $$ExchangeRateOverridesTableCreateCompanionBuilder,
        $$ExchangeRateOverridesTableUpdateCompanionBuilder,
        (
          ExchangeRateOverride,
          BaseReferences<_$BeeDatabase, $ExchangeRateOverridesTable,
              ExchangeRateOverride>
        ),
        ExchangeRateOverride,
        PrefetchHooks Function()>;
typedef $$CardRewardRulesTableCreateCompanionBuilder = CardRewardRulesCompanion
    Function({
  Value<int> id,
  required int accountId,
  Value<String?> syncId,
  required String label,
  Value<String?> categoryIdsJson,
  Value<String> rateType,
  required double rateValue,
  Value<String> rounding,
  Value<String> totalRounding,
  Value<String> calcBasis,
  Value<String> interval,
  Value<double?> minSpendThreshold,
  Value<double?> minTxAmount,
  Value<double?> capAmount,
  Value<String?> capSharedKey,
  Value<DateTime?> startsAt,
  Value<DateTime?> endsAt,
  Value<String> settlementType,
  Value<int?> settlementDays,
  Value<int?> settlementMonthOffset,
  Value<int?> settlementDayOfMonth,
  Value<int?> rewardAccountId,
  Value<String?> note,
  Value<bool> enabled,
  Value<int> sortOrder,
  Value<DateTime?> createdAt,
  Value<DateTime?> updatedAt,
});
typedef $$CardRewardRulesTableUpdateCompanionBuilder = CardRewardRulesCompanion
    Function({
  Value<int> id,
  Value<int> accountId,
  Value<String?> syncId,
  Value<String> label,
  Value<String?> categoryIdsJson,
  Value<String> rateType,
  Value<double> rateValue,
  Value<String> rounding,
  Value<String> totalRounding,
  Value<String> calcBasis,
  Value<String> interval,
  Value<double?> minSpendThreshold,
  Value<double?> minTxAmount,
  Value<double?> capAmount,
  Value<String?> capSharedKey,
  Value<DateTime?> startsAt,
  Value<DateTime?> endsAt,
  Value<String> settlementType,
  Value<int?> settlementDays,
  Value<int?> settlementMonthOffset,
  Value<int?> settlementDayOfMonth,
  Value<int?> rewardAccountId,
  Value<String?> note,
  Value<bool> enabled,
  Value<int> sortOrder,
  Value<DateTime?> createdAt,
  Value<DateTime?> updatedAt,
});

class $$CardRewardRulesTableFilterComposer
    extends Composer<_$BeeDatabase, $CardRewardRulesTable> {
  $$CardRewardRulesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get accountId => $composableBuilder(
      column: $table.accountId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get syncId => $composableBuilder(
      column: $table.syncId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get label => $composableBuilder(
      column: $table.label, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get categoryIdsJson => $composableBuilder(
      column: $table.categoryIdsJson,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get rateType => $composableBuilder(
      column: $table.rateType, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get rateValue => $composableBuilder(
      column: $table.rateValue, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get rounding => $composableBuilder(
      column: $table.rounding, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get totalRounding => $composableBuilder(
      column: $table.totalRounding, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get calcBasis => $composableBuilder(
      column: $table.calcBasis, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get interval => $composableBuilder(
      column: $table.interval, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get minSpendThreshold => $composableBuilder(
      column: $table.minSpendThreshold,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get minTxAmount => $composableBuilder(
      column: $table.minTxAmount, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get capAmount => $composableBuilder(
      column: $table.capAmount, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get capSharedKey => $composableBuilder(
      column: $table.capSharedKey, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get startsAt => $composableBuilder(
      column: $table.startsAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get endsAt => $composableBuilder(
      column: $table.endsAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get settlementType => $composableBuilder(
      column: $table.settlementType,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get settlementDays => $composableBuilder(
      column: $table.settlementDays,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get settlementMonthOffset => $composableBuilder(
      column: $table.settlementMonthOffset,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get settlementDayOfMonth => $composableBuilder(
      column: $table.settlementDayOfMonth,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get rewardAccountId => $composableBuilder(
      column: $table.rewardAccountId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get note => $composableBuilder(
      column: $table.note, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get enabled => $composableBuilder(
      column: $table.enabled, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get sortOrder => $composableBuilder(
      column: $table.sortOrder, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$CardRewardRulesTableOrderingComposer
    extends Composer<_$BeeDatabase, $CardRewardRulesTable> {
  $$CardRewardRulesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get accountId => $composableBuilder(
      column: $table.accountId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get syncId => $composableBuilder(
      column: $table.syncId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get label => $composableBuilder(
      column: $table.label, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get categoryIdsJson => $composableBuilder(
      column: $table.categoryIdsJson,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get rateType => $composableBuilder(
      column: $table.rateType, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get rateValue => $composableBuilder(
      column: $table.rateValue, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get rounding => $composableBuilder(
      column: $table.rounding, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get totalRounding => $composableBuilder(
      column: $table.totalRounding,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get calcBasis => $composableBuilder(
      column: $table.calcBasis, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get interval => $composableBuilder(
      column: $table.interval, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get minSpendThreshold => $composableBuilder(
      column: $table.minSpendThreshold,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get minTxAmount => $composableBuilder(
      column: $table.minTxAmount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get capAmount => $composableBuilder(
      column: $table.capAmount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get capSharedKey => $composableBuilder(
      column: $table.capSharedKey,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get startsAt => $composableBuilder(
      column: $table.startsAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get endsAt => $composableBuilder(
      column: $table.endsAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get settlementType => $composableBuilder(
      column: $table.settlementType,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get settlementDays => $composableBuilder(
      column: $table.settlementDays,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get settlementMonthOffset => $composableBuilder(
      column: $table.settlementMonthOffset,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get settlementDayOfMonth => $composableBuilder(
      column: $table.settlementDayOfMonth,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get rewardAccountId => $composableBuilder(
      column: $table.rewardAccountId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get note => $composableBuilder(
      column: $table.note, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get enabled => $composableBuilder(
      column: $table.enabled, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get sortOrder => $composableBuilder(
      column: $table.sortOrder, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$CardRewardRulesTableAnnotationComposer
    extends Composer<_$BeeDatabase, $CardRewardRulesTable> {
  $$CardRewardRulesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get accountId =>
      $composableBuilder(column: $table.accountId, builder: (column) => column);

  GeneratedColumn<String> get syncId =>
      $composableBuilder(column: $table.syncId, builder: (column) => column);

  GeneratedColumn<String> get label =>
      $composableBuilder(column: $table.label, builder: (column) => column);

  GeneratedColumn<String> get categoryIdsJson => $composableBuilder(
      column: $table.categoryIdsJson, builder: (column) => column);

  GeneratedColumn<String> get rateType =>
      $composableBuilder(column: $table.rateType, builder: (column) => column);

  GeneratedColumn<double> get rateValue =>
      $composableBuilder(column: $table.rateValue, builder: (column) => column);

  GeneratedColumn<String> get rounding =>
      $composableBuilder(column: $table.rounding, builder: (column) => column);

  GeneratedColumn<String> get totalRounding => $composableBuilder(
      column: $table.totalRounding, builder: (column) => column);

  GeneratedColumn<String> get calcBasis =>
      $composableBuilder(column: $table.calcBasis, builder: (column) => column);

  GeneratedColumn<String> get interval =>
      $composableBuilder(column: $table.interval, builder: (column) => column);

  GeneratedColumn<double> get minSpendThreshold => $composableBuilder(
      column: $table.minSpendThreshold, builder: (column) => column);

  GeneratedColumn<double> get minTxAmount => $composableBuilder(
      column: $table.minTxAmount, builder: (column) => column);

  GeneratedColumn<double> get capAmount =>
      $composableBuilder(column: $table.capAmount, builder: (column) => column);

  GeneratedColumn<String> get capSharedKey => $composableBuilder(
      column: $table.capSharedKey, builder: (column) => column);

  GeneratedColumn<DateTime> get startsAt =>
      $composableBuilder(column: $table.startsAt, builder: (column) => column);

  GeneratedColumn<DateTime> get endsAt =>
      $composableBuilder(column: $table.endsAt, builder: (column) => column);

  GeneratedColumn<String> get settlementType => $composableBuilder(
      column: $table.settlementType, builder: (column) => column);

  GeneratedColumn<int> get settlementDays => $composableBuilder(
      column: $table.settlementDays, builder: (column) => column);

  GeneratedColumn<int> get settlementMonthOffset => $composableBuilder(
      column: $table.settlementMonthOffset, builder: (column) => column);

  GeneratedColumn<int> get settlementDayOfMonth => $composableBuilder(
      column: $table.settlementDayOfMonth, builder: (column) => column);

  GeneratedColumn<int> get rewardAccountId => $composableBuilder(
      column: $table.rewardAccountId, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$CardRewardRulesTableTableManager extends RootTableManager<
    _$BeeDatabase,
    $CardRewardRulesTable,
    CardRewardRule,
    $$CardRewardRulesTableFilterComposer,
    $$CardRewardRulesTableOrderingComposer,
    $$CardRewardRulesTableAnnotationComposer,
    $$CardRewardRulesTableCreateCompanionBuilder,
    $$CardRewardRulesTableUpdateCompanionBuilder,
    (
      CardRewardRule,
      BaseReferences<_$BeeDatabase, $CardRewardRulesTable, CardRewardRule>
    ),
    CardRewardRule,
    PrefetchHooks Function()> {
  $$CardRewardRulesTableTableManager(
      _$BeeDatabase db, $CardRewardRulesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CardRewardRulesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CardRewardRulesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CardRewardRulesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<int> accountId = const Value.absent(),
            Value<String?> syncId = const Value.absent(),
            Value<String> label = const Value.absent(),
            Value<String?> categoryIdsJson = const Value.absent(),
            Value<String> rateType = const Value.absent(),
            Value<double> rateValue = const Value.absent(),
            Value<String> rounding = const Value.absent(),
            Value<String> totalRounding = const Value.absent(),
            Value<String> calcBasis = const Value.absent(),
            Value<String> interval = const Value.absent(),
            Value<double?> minSpendThreshold = const Value.absent(),
            Value<double?> minTxAmount = const Value.absent(),
            Value<double?> capAmount = const Value.absent(),
            Value<String?> capSharedKey = const Value.absent(),
            Value<DateTime?> startsAt = const Value.absent(),
            Value<DateTime?> endsAt = const Value.absent(),
            Value<String> settlementType = const Value.absent(),
            Value<int?> settlementDays = const Value.absent(),
            Value<int?> settlementMonthOffset = const Value.absent(),
            Value<int?> settlementDayOfMonth = const Value.absent(),
            Value<int?> rewardAccountId = const Value.absent(),
            Value<String?> note = const Value.absent(),
            Value<bool> enabled = const Value.absent(),
            Value<int> sortOrder = const Value.absent(),
            Value<DateTime?> createdAt = const Value.absent(),
            Value<DateTime?> updatedAt = const Value.absent(),
          }) =>
              CardRewardRulesCompanion(
            id: id,
            accountId: accountId,
            syncId: syncId,
            label: label,
            categoryIdsJson: categoryIdsJson,
            rateType: rateType,
            rateValue: rateValue,
            rounding: rounding,
            totalRounding: totalRounding,
            calcBasis: calcBasis,
            interval: interval,
            minSpendThreshold: minSpendThreshold,
            minTxAmount: minTxAmount,
            capAmount: capAmount,
            capSharedKey: capSharedKey,
            startsAt: startsAt,
            endsAt: endsAt,
            settlementType: settlementType,
            settlementDays: settlementDays,
            settlementMonthOffset: settlementMonthOffset,
            settlementDayOfMonth: settlementDayOfMonth,
            rewardAccountId: rewardAccountId,
            note: note,
            enabled: enabled,
            sortOrder: sortOrder,
            createdAt: createdAt,
            updatedAt: updatedAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required int accountId,
            Value<String?> syncId = const Value.absent(),
            required String label,
            Value<String?> categoryIdsJson = const Value.absent(),
            Value<String> rateType = const Value.absent(),
            required double rateValue,
            Value<String> rounding = const Value.absent(),
            Value<String> totalRounding = const Value.absent(),
            Value<String> calcBasis = const Value.absent(),
            Value<String> interval = const Value.absent(),
            Value<double?> minSpendThreshold = const Value.absent(),
            Value<double?> minTxAmount = const Value.absent(),
            Value<double?> capAmount = const Value.absent(),
            Value<String?> capSharedKey = const Value.absent(),
            Value<DateTime?> startsAt = const Value.absent(),
            Value<DateTime?> endsAt = const Value.absent(),
            Value<String> settlementType = const Value.absent(),
            Value<int?> settlementDays = const Value.absent(),
            Value<int?> settlementMonthOffset = const Value.absent(),
            Value<int?> settlementDayOfMonth = const Value.absent(),
            Value<int?> rewardAccountId = const Value.absent(),
            Value<String?> note = const Value.absent(),
            Value<bool> enabled = const Value.absent(),
            Value<int> sortOrder = const Value.absent(),
            Value<DateTime?> createdAt = const Value.absent(),
            Value<DateTime?> updatedAt = const Value.absent(),
          }) =>
              CardRewardRulesCompanion.insert(
            id: id,
            accountId: accountId,
            syncId: syncId,
            label: label,
            categoryIdsJson: categoryIdsJson,
            rateType: rateType,
            rateValue: rateValue,
            rounding: rounding,
            totalRounding: totalRounding,
            calcBasis: calcBasis,
            interval: interval,
            minSpendThreshold: minSpendThreshold,
            minTxAmount: minTxAmount,
            capAmount: capAmount,
            capSharedKey: capSharedKey,
            startsAt: startsAt,
            endsAt: endsAt,
            settlementType: settlementType,
            settlementDays: settlementDays,
            settlementMonthOffset: settlementMonthOffset,
            settlementDayOfMonth: settlementDayOfMonth,
            rewardAccountId: rewardAccountId,
            note: note,
            enabled: enabled,
            sortOrder: sortOrder,
            createdAt: createdAt,
            updatedAt: updatedAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$CardRewardRulesTableProcessedTableManager = ProcessedTableManager<
    _$BeeDatabase,
    $CardRewardRulesTable,
    CardRewardRule,
    $$CardRewardRulesTableFilterComposer,
    $$CardRewardRulesTableOrderingComposer,
    $$CardRewardRulesTableAnnotationComposer,
    $$CardRewardRulesTableCreateCompanionBuilder,
    $$CardRewardRulesTableUpdateCompanionBuilder,
    (
      CardRewardRule,
      BaseReferences<_$BeeDatabase, $CardRewardRulesTable, CardRewardRule>
    ),
    CardRewardRule,
    PrefetchHooks Function()>;
typedef $$TransactionSplitsTableCreateCompanionBuilder
    = TransactionSplitsCompanion Function({
  Value<int> id,
  required int transactionId,
  Value<int?> categoryId,
  Value<String?> categorySyncIdOverride,
  required double amount,
  Value<String?> note,
  Value<int> sortOrder,
});
typedef $$TransactionSplitsTableUpdateCompanionBuilder
    = TransactionSplitsCompanion Function({
  Value<int> id,
  Value<int> transactionId,
  Value<int?> categoryId,
  Value<String?> categorySyncIdOverride,
  Value<double> amount,
  Value<String?> note,
  Value<int> sortOrder,
});

class $$TransactionSplitsTableFilterComposer
    extends Composer<_$BeeDatabase, $TransactionSplitsTable> {
  $$TransactionSplitsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get transactionId => $composableBuilder(
      column: $table.transactionId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get categoryId => $composableBuilder(
      column: $table.categoryId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get categorySyncIdOverride => $composableBuilder(
      column: $table.categorySyncIdOverride,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get amount => $composableBuilder(
      column: $table.amount, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get note => $composableBuilder(
      column: $table.note, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get sortOrder => $composableBuilder(
      column: $table.sortOrder, builder: (column) => ColumnFilters(column));
}

class $$TransactionSplitsTableOrderingComposer
    extends Composer<_$BeeDatabase, $TransactionSplitsTable> {
  $$TransactionSplitsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get transactionId => $composableBuilder(
      column: $table.transactionId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get categoryId => $composableBuilder(
      column: $table.categoryId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get categorySyncIdOverride => $composableBuilder(
      column: $table.categorySyncIdOverride,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get amount => $composableBuilder(
      column: $table.amount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get note => $composableBuilder(
      column: $table.note, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get sortOrder => $composableBuilder(
      column: $table.sortOrder, builder: (column) => ColumnOrderings(column));
}

class $$TransactionSplitsTableAnnotationComposer
    extends Composer<_$BeeDatabase, $TransactionSplitsTable> {
  $$TransactionSplitsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get transactionId => $composableBuilder(
      column: $table.transactionId, builder: (column) => column);

  GeneratedColumn<int> get categoryId => $composableBuilder(
      column: $table.categoryId, builder: (column) => column);

  GeneratedColumn<String> get categorySyncIdOverride => $composableBuilder(
      column: $table.categorySyncIdOverride, builder: (column) => column);

  GeneratedColumn<double> get amount =>
      $composableBuilder(column: $table.amount, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);
}

class $$TransactionSplitsTableTableManager extends RootTableManager<
    _$BeeDatabase,
    $TransactionSplitsTable,
    TransactionSplit,
    $$TransactionSplitsTableFilterComposer,
    $$TransactionSplitsTableOrderingComposer,
    $$TransactionSplitsTableAnnotationComposer,
    $$TransactionSplitsTableCreateCompanionBuilder,
    $$TransactionSplitsTableUpdateCompanionBuilder,
    (
      TransactionSplit,
      BaseReferences<_$BeeDatabase, $TransactionSplitsTable, TransactionSplit>
    ),
    TransactionSplit,
    PrefetchHooks Function()> {
  $$TransactionSplitsTableTableManager(
      _$BeeDatabase db, $TransactionSplitsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TransactionSplitsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TransactionSplitsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TransactionSplitsTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<int> transactionId = const Value.absent(),
            Value<int?> categoryId = const Value.absent(),
            Value<String?> categorySyncIdOverride = const Value.absent(),
            Value<double> amount = const Value.absent(),
            Value<String?> note = const Value.absent(),
            Value<int> sortOrder = const Value.absent(),
          }) =>
              TransactionSplitsCompanion(
            id: id,
            transactionId: transactionId,
            categoryId: categoryId,
            categorySyncIdOverride: categorySyncIdOverride,
            amount: amount,
            note: note,
            sortOrder: sortOrder,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required int transactionId,
            Value<int?> categoryId = const Value.absent(),
            Value<String?> categorySyncIdOverride = const Value.absent(),
            required double amount,
            Value<String?> note = const Value.absent(),
            Value<int> sortOrder = const Value.absent(),
          }) =>
              TransactionSplitsCompanion.insert(
            id: id,
            transactionId: transactionId,
            categoryId: categoryId,
            categorySyncIdOverride: categorySyncIdOverride,
            amount: amount,
            note: note,
            sortOrder: sortOrder,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$TransactionSplitsTableProcessedTableManager = ProcessedTableManager<
    _$BeeDatabase,
    $TransactionSplitsTable,
    TransactionSplit,
    $$TransactionSplitsTableFilterComposer,
    $$TransactionSplitsTableOrderingComposer,
    $$TransactionSplitsTableAnnotationComposer,
    $$TransactionSplitsTableCreateCompanionBuilder,
    $$TransactionSplitsTableUpdateCompanionBuilder,
    (
      TransactionSplit,
      BaseReferences<_$BeeDatabase, $TransactionSplitsTable, TransactionSplit>
    ),
    TransactionSplit,
    PrefetchHooks Function()>;
typedef $$DebtsTableCreateCompanionBuilder = DebtsCompanion Function({
  Value<int> id,
  Value<String?> syncId,
  required int ledgerId,
  required String direction,
  required String counterpartyName,
  required double principalAmount,
  Value<DateTime?> dueAt,
  Value<String?> note,
  Value<DateTime?> closedAt,
  Value<int?> categoryId,
  Value<String?> originTransactionSyncId,
  Value<bool> excludedFromTotal,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
});
typedef $$DebtsTableUpdateCompanionBuilder = DebtsCompanion Function({
  Value<int> id,
  Value<String?> syncId,
  Value<int> ledgerId,
  Value<String> direction,
  Value<String> counterpartyName,
  Value<double> principalAmount,
  Value<DateTime?> dueAt,
  Value<String?> note,
  Value<DateTime?> closedAt,
  Value<int?> categoryId,
  Value<String?> originTransactionSyncId,
  Value<bool> excludedFromTotal,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
});

class $$DebtsTableFilterComposer extends Composer<_$BeeDatabase, $DebtsTable> {
  $$DebtsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get syncId => $composableBuilder(
      column: $table.syncId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get ledgerId => $composableBuilder(
      column: $table.ledgerId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get direction => $composableBuilder(
      column: $table.direction, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get counterpartyName => $composableBuilder(
      column: $table.counterpartyName,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get principalAmount => $composableBuilder(
      column: $table.principalAmount,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get dueAt => $composableBuilder(
      column: $table.dueAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get note => $composableBuilder(
      column: $table.note, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get closedAt => $composableBuilder(
      column: $table.closedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get categoryId => $composableBuilder(
      column: $table.categoryId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get originTransactionSyncId => $composableBuilder(
      column: $table.originTransactionSyncId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get excludedFromTotal => $composableBuilder(
      column: $table.excludedFromTotal,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$DebtsTableOrderingComposer
    extends Composer<_$BeeDatabase, $DebtsTable> {
  $$DebtsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get syncId => $composableBuilder(
      column: $table.syncId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get ledgerId => $composableBuilder(
      column: $table.ledgerId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get direction => $composableBuilder(
      column: $table.direction, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get counterpartyName => $composableBuilder(
      column: $table.counterpartyName,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get principalAmount => $composableBuilder(
      column: $table.principalAmount,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get dueAt => $composableBuilder(
      column: $table.dueAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get note => $composableBuilder(
      column: $table.note, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get closedAt => $composableBuilder(
      column: $table.closedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get categoryId => $composableBuilder(
      column: $table.categoryId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get originTransactionSyncId => $composableBuilder(
      column: $table.originTransactionSyncId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get excludedFromTotal => $composableBuilder(
      column: $table.excludedFromTotal,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$DebtsTableAnnotationComposer
    extends Composer<_$BeeDatabase, $DebtsTable> {
  $$DebtsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get syncId =>
      $composableBuilder(column: $table.syncId, builder: (column) => column);

  GeneratedColumn<int> get ledgerId =>
      $composableBuilder(column: $table.ledgerId, builder: (column) => column);

  GeneratedColumn<String> get direction =>
      $composableBuilder(column: $table.direction, builder: (column) => column);

  GeneratedColumn<String> get counterpartyName => $composableBuilder(
      column: $table.counterpartyName, builder: (column) => column);

  GeneratedColumn<double> get principalAmount => $composableBuilder(
      column: $table.principalAmount, builder: (column) => column);

  GeneratedColumn<DateTime> get dueAt =>
      $composableBuilder(column: $table.dueAt, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<DateTime> get closedAt =>
      $composableBuilder(column: $table.closedAt, builder: (column) => column);

  GeneratedColumn<int> get categoryId => $composableBuilder(
      column: $table.categoryId, builder: (column) => column);

  GeneratedColumn<String> get originTransactionSyncId => $composableBuilder(
      column: $table.originTransactionSyncId, builder: (column) => column);

  GeneratedColumn<bool> get excludedFromTotal => $composableBuilder(
      column: $table.excludedFromTotal, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$DebtsTableTableManager extends RootTableManager<
    _$BeeDatabase,
    $DebtsTable,
    Debt,
    $$DebtsTableFilterComposer,
    $$DebtsTableOrderingComposer,
    $$DebtsTableAnnotationComposer,
    $$DebtsTableCreateCompanionBuilder,
    $$DebtsTableUpdateCompanionBuilder,
    (Debt, BaseReferences<_$BeeDatabase, $DebtsTable, Debt>),
    Debt,
    PrefetchHooks Function()> {
  $$DebtsTableTableManager(_$BeeDatabase db, $DebtsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DebtsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DebtsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DebtsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String?> syncId = const Value.absent(),
            Value<int> ledgerId = const Value.absent(),
            Value<String> direction = const Value.absent(),
            Value<String> counterpartyName = const Value.absent(),
            Value<double> principalAmount = const Value.absent(),
            Value<DateTime?> dueAt = const Value.absent(),
            Value<String?> note = const Value.absent(),
            Value<DateTime?> closedAt = const Value.absent(),
            Value<int?> categoryId = const Value.absent(),
            Value<String?> originTransactionSyncId = const Value.absent(),
            Value<bool> excludedFromTotal = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
          }) =>
              DebtsCompanion(
            id: id,
            syncId: syncId,
            ledgerId: ledgerId,
            direction: direction,
            counterpartyName: counterpartyName,
            principalAmount: principalAmount,
            dueAt: dueAt,
            note: note,
            closedAt: closedAt,
            categoryId: categoryId,
            originTransactionSyncId: originTransactionSyncId,
            excludedFromTotal: excludedFromTotal,
            createdAt: createdAt,
            updatedAt: updatedAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String?> syncId = const Value.absent(),
            required int ledgerId,
            required String direction,
            required String counterpartyName,
            required double principalAmount,
            Value<DateTime?> dueAt = const Value.absent(),
            Value<String?> note = const Value.absent(),
            Value<DateTime?> closedAt = const Value.absent(),
            Value<int?> categoryId = const Value.absent(),
            Value<String?> originTransactionSyncId = const Value.absent(),
            Value<bool> excludedFromTotal = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
          }) =>
              DebtsCompanion.insert(
            id: id,
            syncId: syncId,
            ledgerId: ledgerId,
            direction: direction,
            counterpartyName: counterpartyName,
            principalAmount: principalAmount,
            dueAt: dueAt,
            note: note,
            closedAt: closedAt,
            categoryId: categoryId,
            originTransactionSyncId: originTransactionSyncId,
            excludedFromTotal: excludedFromTotal,
            createdAt: createdAt,
            updatedAt: updatedAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$DebtsTableProcessedTableManager = ProcessedTableManager<
    _$BeeDatabase,
    $DebtsTable,
    Debt,
    $$DebtsTableFilterComposer,
    $$DebtsTableOrderingComposer,
    $$DebtsTableAnnotationComposer,
    $$DebtsTableCreateCompanionBuilder,
    $$DebtsTableUpdateCompanionBuilder,
    (Debt, BaseReferences<_$BeeDatabase, $DebtsTable, Debt>),
    Debt,
    PrefetchHooks Function()>;
typedef $$ProjectsTableCreateCompanionBuilder = ProjectsCompanion Function({
  Value<int> id,
  Value<String?> syncId,
  required int ledgerId,
  Value<String> name,
  Value<String?> icon,
  Value<double?> budgetAmount,
  Value<String> periodType,
  Value<DateTime?> periodStart,
  Value<DateTime?> periodEnd,
  Value<bool> carryoverEnabled,
  Value<bool> visibleOnHome,
  Value<bool> enabled,
  Value<int> sortOrder,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
});
typedef $$ProjectsTableUpdateCompanionBuilder = ProjectsCompanion Function({
  Value<int> id,
  Value<String?> syncId,
  Value<int> ledgerId,
  Value<String> name,
  Value<String?> icon,
  Value<double?> budgetAmount,
  Value<String> periodType,
  Value<DateTime?> periodStart,
  Value<DateTime?> periodEnd,
  Value<bool> carryoverEnabled,
  Value<bool> visibleOnHome,
  Value<bool> enabled,
  Value<int> sortOrder,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
});

class $$ProjectsTableFilterComposer
    extends Composer<_$BeeDatabase, $ProjectsTable> {
  $$ProjectsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get syncId => $composableBuilder(
      column: $table.syncId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get ledgerId => $composableBuilder(
      column: $table.ledgerId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get icon => $composableBuilder(
      column: $table.icon, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get budgetAmount => $composableBuilder(
      column: $table.budgetAmount, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get periodType => $composableBuilder(
      column: $table.periodType, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get periodStart => $composableBuilder(
      column: $table.periodStart, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get periodEnd => $composableBuilder(
      column: $table.periodEnd, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get carryoverEnabled => $composableBuilder(
      column: $table.carryoverEnabled,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get visibleOnHome => $composableBuilder(
      column: $table.visibleOnHome, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get enabled => $composableBuilder(
      column: $table.enabled, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get sortOrder => $composableBuilder(
      column: $table.sortOrder, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$ProjectsTableOrderingComposer
    extends Composer<_$BeeDatabase, $ProjectsTable> {
  $$ProjectsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get syncId => $composableBuilder(
      column: $table.syncId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get ledgerId => $composableBuilder(
      column: $table.ledgerId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get icon => $composableBuilder(
      column: $table.icon, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get budgetAmount => $composableBuilder(
      column: $table.budgetAmount,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get periodType => $composableBuilder(
      column: $table.periodType, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get periodStart => $composableBuilder(
      column: $table.periodStart, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get periodEnd => $composableBuilder(
      column: $table.periodEnd, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get carryoverEnabled => $composableBuilder(
      column: $table.carryoverEnabled,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get visibleOnHome => $composableBuilder(
      column: $table.visibleOnHome,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get enabled => $composableBuilder(
      column: $table.enabled, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get sortOrder => $composableBuilder(
      column: $table.sortOrder, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$ProjectsTableAnnotationComposer
    extends Composer<_$BeeDatabase, $ProjectsTable> {
  $$ProjectsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get syncId =>
      $composableBuilder(column: $table.syncId, builder: (column) => column);

  GeneratedColumn<int> get ledgerId =>
      $composableBuilder(column: $table.ledgerId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get icon =>
      $composableBuilder(column: $table.icon, builder: (column) => column);

  GeneratedColumn<double> get budgetAmount => $composableBuilder(
      column: $table.budgetAmount, builder: (column) => column);

  GeneratedColumn<String> get periodType => $composableBuilder(
      column: $table.periodType, builder: (column) => column);

  GeneratedColumn<DateTime> get periodStart => $composableBuilder(
      column: $table.periodStart, builder: (column) => column);

  GeneratedColumn<DateTime> get periodEnd =>
      $composableBuilder(column: $table.periodEnd, builder: (column) => column);

  GeneratedColumn<bool> get carryoverEnabled => $composableBuilder(
      column: $table.carryoverEnabled, builder: (column) => column);

  GeneratedColumn<bool> get visibleOnHome => $composableBuilder(
      column: $table.visibleOnHome, builder: (column) => column);

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$ProjectsTableTableManager extends RootTableManager<
    _$BeeDatabase,
    $ProjectsTable,
    Project,
    $$ProjectsTableFilterComposer,
    $$ProjectsTableOrderingComposer,
    $$ProjectsTableAnnotationComposer,
    $$ProjectsTableCreateCompanionBuilder,
    $$ProjectsTableUpdateCompanionBuilder,
    (Project, BaseReferences<_$BeeDatabase, $ProjectsTable, Project>),
    Project,
    PrefetchHooks Function()> {
  $$ProjectsTableTableManager(_$BeeDatabase db, $ProjectsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProjectsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProjectsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProjectsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String?> syncId = const Value.absent(),
            Value<int> ledgerId = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String?> icon = const Value.absent(),
            Value<double?> budgetAmount = const Value.absent(),
            Value<String> periodType = const Value.absent(),
            Value<DateTime?> periodStart = const Value.absent(),
            Value<DateTime?> periodEnd = const Value.absent(),
            Value<bool> carryoverEnabled = const Value.absent(),
            Value<bool> visibleOnHome = const Value.absent(),
            Value<bool> enabled = const Value.absent(),
            Value<int> sortOrder = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
          }) =>
              ProjectsCompanion(
            id: id,
            syncId: syncId,
            ledgerId: ledgerId,
            name: name,
            icon: icon,
            budgetAmount: budgetAmount,
            periodType: periodType,
            periodStart: periodStart,
            periodEnd: periodEnd,
            carryoverEnabled: carryoverEnabled,
            visibleOnHome: visibleOnHome,
            enabled: enabled,
            sortOrder: sortOrder,
            createdAt: createdAt,
            updatedAt: updatedAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String?> syncId = const Value.absent(),
            required int ledgerId,
            Value<String> name = const Value.absent(),
            Value<String?> icon = const Value.absent(),
            Value<double?> budgetAmount = const Value.absent(),
            Value<String> periodType = const Value.absent(),
            Value<DateTime?> periodStart = const Value.absent(),
            Value<DateTime?> periodEnd = const Value.absent(),
            Value<bool> carryoverEnabled = const Value.absent(),
            Value<bool> visibleOnHome = const Value.absent(),
            Value<bool> enabled = const Value.absent(),
            Value<int> sortOrder = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
          }) =>
              ProjectsCompanion.insert(
            id: id,
            syncId: syncId,
            ledgerId: ledgerId,
            name: name,
            icon: icon,
            budgetAmount: budgetAmount,
            periodType: periodType,
            periodStart: periodStart,
            periodEnd: periodEnd,
            carryoverEnabled: carryoverEnabled,
            visibleOnHome: visibleOnHome,
            enabled: enabled,
            sortOrder: sortOrder,
            createdAt: createdAt,
            updatedAt: updatedAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$ProjectsTableProcessedTableManager = ProcessedTableManager<
    _$BeeDatabase,
    $ProjectsTable,
    Project,
    $$ProjectsTableFilterComposer,
    $$ProjectsTableOrderingComposer,
    $$ProjectsTableAnnotationComposer,
    $$ProjectsTableCreateCompanionBuilder,
    $$ProjectsTableUpdateCompanionBuilder,
    (Project, BaseReferences<_$BeeDatabase, $ProjectsTable, Project>),
    Project,
    PrefetchHooks Function()>;

class $BeeDatabaseManager {
  final _$BeeDatabase _db;
  $BeeDatabaseManager(this._db);
  $$LedgersTableTableManager get ledgers =>
      $$LedgersTableTableManager(_db, _db.ledgers);
  $$AccountsTableTableManager get accounts =>
      $$AccountsTableTableManager(_db, _db.accounts);
  $$CategoriesTableTableManager get categories =>
      $$CategoriesTableTableManager(_db, _db.categories);
  $$TransactionsTableTableManager get transactions =>
      $$TransactionsTableTableManager(_db, _db.transactions);
  $$RecurringTransactionsTableTableManager get recurringTransactions =>
      $$RecurringTransactionsTableTableManager(_db, _db.recurringTransactions);
  $$ConversationsTableTableManager get conversations =>
      $$ConversationsTableTableManager(_db, _db.conversations);
  $$MessagesTableTableManager get messages =>
      $$MessagesTableTableManager(_db, _db.messages);
  $$TagsTableTableManager get tags => $$TagsTableTableManager(_db, _db.tags);
  $$TransactionTagsTableTableManager get transactionTags =>
      $$TransactionTagsTableTableManager(_db, _db.transactionTags);
  $$BudgetsTableTableManager get budgets =>
      $$BudgetsTableTableManager(_db, _db.budgets);
  $$TransactionAttachmentsTableTableManager get transactionAttachments =>
      $$TransactionAttachmentsTableTableManager(
          _db, _db.transactionAttachments);
  $$LocalChangesTableTableManager get localChanges =>
      $$LocalChangesTableTableManager(_db, _db.localChanges);
  $$SyncStateTableTableManager get syncState =>
      $$SyncStateTableTableManager(_db, _db.syncState);
  $$LedgerMembersTableTableManager get ledgerMembers =>
      $$LedgerMembersTableTableManager(_db, _db.ledgerMembers);
  $$SharedLedgerCategoriesTableTableManager get sharedLedgerCategories =>
      $$SharedLedgerCategoriesTableTableManager(
          _db, _db.sharedLedgerCategories);
  $$SharedLedgerAccountsTableTableManager get sharedLedgerAccounts =>
      $$SharedLedgerAccountsTableTableManager(_db, _db.sharedLedgerAccounts);
  $$SharedLedgerTagsTableTableManager get sharedLedgerTags =>
      $$SharedLedgerTagsTableTableManager(_db, _db.sharedLedgerTags);
  $$TransactionTagOverridesTableTableManager get transactionTagOverrides =>
      $$TransactionTagOverridesTableTableManager(
          _db, _db.transactionTagOverrides);
  $$SyncPullErrorsTableTableManager get syncPullErrors =>
      $$SyncPullErrorsTableTableManager(_db, _db.syncPullErrors);
  $$ExchangeRatesTableTableManager get exchangeRates =>
      $$ExchangeRatesTableTableManager(_db, _db.exchangeRates);
  $$ExchangeRateOverridesTableTableManager get exchangeRateOverrides =>
      $$ExchangeRateOverridesTableTableManager(_db, _db.exchangeRateOverrides);
  $$CardRewardRulesTableTableManager get cardRewardRules =>
      $$CardRewardRulesTableTableManager(_db, _db.cardRewardRules);
  $$TransactionSplitsTableTableManager get transactionSplits =>
      $$TransactionSplitsTableTableManager(_db, _db.transactionSplits);
  $$DebtsTableTableManager get debts =>
      $$DebtsTableTableManager(_db, _db.debts);
  $$ProjectsTableTableManager get projects =>
      $$ProjectsTableTableManager(_db, _db.projects);
}
