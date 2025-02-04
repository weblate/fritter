import 'package:flutter/material.dart';
import 'package:fritter/client.dart';
import 'package:fritter/constants.dart';
import 'package:fritter/database/entities.dart';
import 'package:fritter/database/repository.dart';
import 'package:fritter/group/group_model.dart';
import 'package:logging/logging.dart';
import 'package:pref/pref.dart';

class UsersModel extends ChangeNotifier {
  static final log = Logger('UsersModel');

  List<Subscription> _subscriptions = [];
  Set<String> _subscriptionIds = Set();

  final BasePrefService _prefs;
  final GroupModel _groupModel;

  UsersModel(this._prefs, this._groupModel);

  bool get orderSubscriptionsAscending => _prefs.get(OPTION_SUBSCRIPTION_ORDER_BY_ASCENDING);
  String get orderSubscriptions => _prefs.get(OPTION_SUBSCRIPTION_ORDER_BY_FIELD);
  List<Subscription> get subscriptions => List.unmodifiable(_subscriptions);
  List<String> get subscriptionIds => List.unmodifiable(_subscriptionIds);

  Future reloadSubscriptions() async {
    log.info('Listing subscriptions');

    var database = await Repository.readOnly();

    var orderByDirection = orderSubscriptionsAscending
        ? 'COLLATE NOCASE ASC'
        : 'COLLATE NOCASE DESC';

    _subscriptions = (await database.query(TABLE_SUBSCRIPTION, orderBy: '$orderSubscriptions $orderByDirection'))
        .map((e) => Subscription.fromMap(e))
        .toList(growable: false);

    _subscriptionIds = _subscriptions.map((e) => e.id).toSet();

    notifyListeners();
  }

  Future refreshSubscriptionData() async {
    var database = await Repository.writable();

    var ids = (await database.query(TABLE_SUBSCRIPTION, columns: ['id']))
        .map((e) => e['id'] as String)
        .toList();

    var users = await Twitter.getUsers(ids);

    var batch = database.batch();
    for (var user in users) {
      batch.update(TABLE_SUBSCRIPTION, {
        'screen_name': user.screenName,
        'name': user.name,
        'profile_image_url_https': user.profileImageUrlHttps,
        'verified': (user.verified ?? false) ? 1 : 0
      }, where: 'id = ?', whereArgs: [user.idStr]);
    }

    await batch.commit();
    await reloadSubscriptions();
  }

  Future toggleSubscribe(String id, String screenName, String name, String? imageUri, bool verified, bool currentlyFollowed) async {
    var database = await Repository.writable();

    if (currentlyFollowed) {
      await database.delete(TABLE_SUBSCRIPTION, where: 'id = ?', whereArgs: [id]);
      await database.delete(TABLE_SUBSCRIPTION_GROUP_MEMBER, where: 'profile_id = ?', whereArgs: [id]);
    } else {
      await database.insert(TABLE_SUBSCRIPTION, {
        'id': id,
        'screen_name': screenName,
        'name': name,
        'profile_image_url_https': imageUri,
        'verified': verified
      });
    }

    await reloadSubscriptions();
    await _groupModel.reloadGroups();
  }

  void changeOrderSubscriptionsBy(String? value) async {
    await _prefs.set(OPTION_SUBSCRIPTION_ORDER_BY_FIELD, value ?? 'name');
    await reloadSubscriptions();
  }

  void toggleOrderSubscriptionsAscending() async {
    await _prefs.set(OPTION_SUBSCRIPTION_ORDER_BY_ASCENDING, !orderSubscriptionsAscending);
    await reloadSubscriptions();
  }
}