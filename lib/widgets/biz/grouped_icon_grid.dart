import 'package:flutter/material.dart';

class GroupedIconGrid extends StatelessWidget {
  final String? selectedIcon;
  final String kind;
  final ValueChanged<String> onIconSelected;

  const GroupedIconGrid({
    super.key,
    required this.selectedIcon,
    required this.kind,
    required this.onIconSelected,
  });

  @override
  Widget build(BuildContext context) {
    final iconGroups = _getIconGroups();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: iconGroups.map((group) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                group.title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 6,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 1,
              ),
              itemCount: group.icons.length,
              itemBuilder: (context, index) {
                final iconData = group.icons[index];
                final isSelected = selectedIcon == iconData.key;

                return InkWell(
                  onTap: () => onIconSelected(iconData.key),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: 0.1)
                          : null,
                      border: Border.all(
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey.withValues(alpha: 0.3),
                        width: isSelected ? 2 : 1,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      iconData.iconData,
                      size: 20,
                      color: isSelected
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).iconTheme.color,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
          ],
        );
      }).toList(),
    );
  }

  List<IconGroupData> _getIconGroups() {
    if (kind == 'expense') {
      return [
        IconGroupData('基础', [
          IconEntry('category', Icons.category),
          IconEntry('label', Icons.label),
          IconEntry('bookmark', Icons.bookmark),
          IconEntry('star', Icons.star),
          IconEntry('favorite', Icons.favorite),
          IconEntry('circle', Icons.circle),
        ]),
        IconGroupData('餐饮美食', [
          IconEntry('restaurant', Icons.restaurant),
          IconEntry('local_dining', Icons.local_dining),
          IconEntry('fastfood', Icons.fastfood),
          IconEntry('local_cafe', Icons.local_cafe),
          IconEntry('local_bar', Icons.local_bar),
          IconEntry('local_pizza', Icons.local_pizza),
          IconEntry('cake', Icons.cake),
          IconEntry('coffee', Icons.coffee),
          IconEntry('breakfast_dining', Icons.breakfast_dining),
          IconEntry('lunch_dining', Icons.lunch_dining),
          IconEntry('dinner_dining', Icons.dinner_dining),
          IconEntry('icecream', Icons.icecream),
          IconEntry('bakery_dining', Icons.bakery_dining),
          IconEntry('liquor', Icons.liquor),
          IconEntry('wine_bar', Icons.wine_bar),
          IconEntry('restaurant_menu', Icons.restaurant_menu),
          IconEntry('set_meal', Icons.set_meal),
          IconEntry('ramen_dining', Icons.ramen_dining),
        ]),
        IconGroupData('交通出行', [
          IconEntry('directions_car', Icons.directions_car),
          IconEntry('directions_bus', Icons.directions_bus),
          IconEntry('directions_subway', Icons.directions_subway),
          IconEntry('local_taxi', Icons.local_taxi),
          IconEntry('flight', Icons.flight),
          IconEntry('train', Icons.train),
          IconEntry('motorcycle', Icons.motorcycle),
          IconEntry('directions_bike', Icons.directions_bike),
          IconEntry('directions_walk', Icons.directions_walk),
          IconEntry('boat', Icons.directions_boat),
          IconEntry('electric_scooter', Icons.electric_scooter),
          IconEntry('local_gas_station', Icons.local_gas_station),
          IconEntry('local_parking', Icons.local_parking),
          IconEntry('traffic', Icons.traffic),
          IconEntry('directions_railway', Icons.directions_railway),
          IconEntry('airport_shuttle', Icons.airport_shuttle),
          IconEntry('pedal_bike', Icons.pedal_bike),
          IconEntry('car_rental', Icons.car_rental),
        ]),
        IconGroupData('购物消费', [
          IconEntry('shopping_cart', Icons.shopping_cart),
          IconEntry('shopping_bag', Icons.shopping_bag),
          IconEntry('store', Icons.store),
          IconEntry('local_mall', Icons.local_mall),
          IconEntry('local_grocery_store', Icons.local_grocery_store),
          IconEntry('storefront', Icons.storefront),
          IconEntry('shopping_basket', Icons.shopping_basket),
          IconEntry('local_offer', Icons.local_offer),
          IconEntry('receipt', Icons.receipt),
          IconEntry('sell', Icons.sell),
          IconEntry('price_check', Icons.price_check),
          IconEntry('card_giftcard', Icons.card_giftcard),
          IconEntry('redeem', Icons.redeem),
          IconEntry('inventory', Icons.inventory),
          IconEntry('add_shopping_cart', Icons.add_shopping_cart),
          IconEntry('loyalty', Icons.loyalty),
        ]),
        IconGroupData('居住生活', [
          IconEntry('home', Icons.home),
          IconEntry('house', Icons.house),
          IconEntry('apartment', Icons.apartment),
          IconEntry('cleaning_services', Icons.cleaning_services),
          IconEntry('plumbing', Icons.plumbing),
          IconEntry('electrical_services', Icons.electrical_services),
          IconEntry('flash_on', Icons.flash_on),
          IconEntry('water_drop', Icons.water_drop),
          IconEntry('air', Icons.air),
          IconEntry('kitchen', Icons.kitchen),
          IconEntry('bathtub', Icons.bathtub),
          IconEntry('bed', Icons.bed),
          IconEntry('chair', Icons.chair),
          IconEntry('table_restaurant', Icons.table_restaurant),
          IconEntry('lightbulb', Icons.lightbulb),
          IconEntry('hvac', Icons.hvac),
          IconEntry('roofing', Icons.roofing),
          IconEntry('foundation', Icons.foundation),
        ]),
        IconGroupData('通讯设备', [
          IconEntry('phone', Icons.phone),
          IconEntry('smartphone', Icons.smartphone),
          IconEntry('phone_android', Icons.phone_android),
          IconEntry('phone_iphone', Icons.phone_iphone),
          IconEntry('tablet', Icons.tablet),
          IconEntry('laptop', Icons.laptop),
          IconEntry('computer', Icons.computer),
          IconEntry('desktop_windows', Icons.desktop_windows),
          IconEntry('watch', Icons.watch),
          IconEntry('headphones', Icons.headphones),
          IconEntry('headset', Icons.headset),
          IconEntry('keyboard', Icons.keyboard),
          IconEntry('mouse', Icons.mouse),
          IconEntry('wifi', Icons.wifi),
          IconEntry('router', Icons.router),
          IconEntry('cable', Icons.cable),
        ]),
        IconGroupData('娱乐休闲', [
          IconEntry('movie', Icons.movie),
          IconEntry('music_note', Icons.music_note),
          IconEntry('sports_esports', Icons.sports_esports),
          IconEntry('theater_comedy', Icons.theater_comedy),
          IconEntry('casino', Icons.casino),
          IconEntry('celebration', Icons.celebration),
          IconEntry('party_mode', Icons.party_mode),
          IconEntry('nightlife', Icons.nightlife),
          IconEntry('local_activity', Icons.local_activity),
          IconEntry('attractions', Icons.attractions),
          IconEntry('beach_access', Icons.beach_access),
          IconEntry('pool', Icons.pool),
          IconEntry('spa', Icons.spa),
          IconEntry('games', Icons.games),
          IconEntry('sports', Icons.sports),
          IconEntry('sports_soccer', Icons.sports_soccer),
          IconEntry('sports_basketball', Icons.sports_basketball),
          IconEntry('sports_tennis', Icons.sports_tennis),
        ]),
        IconGroupData('健康医疗', [
          IconEntry('local_hospital', Icons.local_hospital),
          IconEntry('medical_services', Icons.medical_services),
          IconEntry('local_pharmacy', Icons.local_pharmacy),
          IconEntry('health_and_safety', Icons.health_and_safety),
          IconEntry('medication', Icons.medication),
          IconEntry('fitness_center', Icons.fitness_center),
          IconEntry('self_improvement', Icons.self_improvement),
          IconEntry('psychology', Icons.psychology),
          IconEntry('healing', Icons.healing),
          IconEntry('monitor_heart', Icons.monitor_heart),
          IconEntry('elderly', Icons.elderly),
          IconEntry('accessible', Icons.accessible),
          IconEntry('medical_information', Icons.medical_information),
          IconEntry('biotech', Icons.biotech),
          IconEntry('coronavirus', Icons.coronavirus),
          IconEntry('vaccines', Icons.vaccines),
        ]),
        IconGroupData('教育学习', [
          IconEntry('school', Icons.school),
          IconEntry('book', Icons.book),
          IconEntry('library_books', Icons.library_books),
          IconEntry('menu_book', Icons.menu_book),
          IconEntry('auto_stories', Icons.auto_stories),
          IconEntry('edit', Icons.edit),
          IconEntry('create', Icons.create),
          IconEntry('calculate', Icons.calculate),
          IconEntry('science', Icons.science),
          IconEntry('brush', Icons.brush),
          IconEntry('palette', Icons.palette),
          IconEntry('music_video', Icons.music_video),
          IconEntry('piano', Icons.piano),
          IconEntry('translate', Icons.translate),
          IconEntry('language', Icons.language),
          IconEntry('quiz', Icons.quiz),
        ]),
        IconGroupData('宠物动物', [
          IconEntry('pets', Icons.pets),
          IconEntry('cruelty_free', Icons.cruelty_free),
          IconEntry('bug_report', Icons.bug_report),
          IconEntry('emoji_nature', Icons.emoji_nature),
          IconEntry('park', Icons.park),
          IconEntry('grass', Icons.grass),
          IconEntry('forest', Icons.forest),
          IconEntry('agriculture', Icons.agriculture),
          IconEntry('eco', Icons.eco),
          IconEntry('local_florist', Icons.local_florist),
          IconEntry('yard', Icons.yard),
        ]),
        IconGroupData('服装美容', [
          IconEntry('checkroom', Icons.checkroom),
          IconEntry('face', Icons.face),
          IconEntry('face_retouching', Icons.face),
          IconEntry('content_cut', Icons.content_cut),
          IconEntry('dry_cleaning', Icons.dry_cleaning),
          IconEntry('local_laundry_service', Icons.local_laundry_service),
          IconEntry('iron', Icons.iron),
          IconEntry('diamond', Icons.diamond),
          IconEntry('watch_later', Icons.watch_later),
          IconEntry('ring_volume', Icons.ring_volume),
          IconEntry('gesture', Icons.gesture),
        ]),
        IconGroupData('其他杂项', [
          IconEntry('business', Icons.business),
          IconEntry('work', Icons.work),
          IconEntry('camera_alt', Icons.camera_alt),
          IconEntry('photo_camera', Icons.photo_camera),
          IconEntry('videocam', Icons.videocam),
          IconEntry('print', Icons.print),
          IconEntry('mail', Icons.mail),
          IconEntry('local_post_office', Icons.local_post_office),
          IconEntry('public', Icons.public),
          IconEntry('place', Icons.place),
          IconEntry('location_on', Icons.location_on),
          IconEntry('map', Icons.map),
          IconEntry('explore', Icons.explore),
          IconEntry('compass', Icons.explore),
          IconEntry('schedule', Icons.schedule),
          IconEntry('access_time', Icons.access_time),
        ]),
      ];
    } else {
      return [
        IconGroupData('基础', [
          IconEntry('category', Icons.category),
          IconEntry('label', Icons.label),
          IconEntry('bookmark', Icons.bookmark),
          IconEntry('star', Icons.star),
          IconEntry('favorite', Icons.favorite),
          IconEntry('circle', Icons.circle),
        ]),
        IconGroupData('工作职业', [
          IconEntry('work', Icons.work),
          IconEntry('business', Icons.business),
          IconEntry('business_center', Icons.business_center),
          IconEntry('engineering', Icons.engineering),
          IconEntry('design_services', Icons.design_services),
          IconEntry('construction', Icons.construction),
          IconEntry('code', Icons.code),
          IconEntry('developer_mode', Icons.developer_mode),
          IconEntry('computer', Icons.computer),
          IconEntry('laptop', Icons.laptop),
          IconEntry('biotech', Icons.biotech),
          IconEntry('science', Icons.science),
          IconEntry('psychology', Icons.psychology),
          IconEntry('medical_services', Icons.medical_services),
          IconEntry('school', Icons.school),
          IconEntry('gavel', Icons.gavel),
          IconEntry('balance', Icons.balance),
          IconEntry('support_agent', Icons.support_agent),
        ]),
        IconGroupData('金融理财', [
          IconEntry('account_balance', Icons.account_balance),
          IconEntry('account_balance_wallet', Icons.account_balance_wallet),
          IconEntry('savings', Icons.savings),
          IconEntry('trending_up', Icons.trending_up),
          IconEntry('trending_down', Icons.trending_down),
          IconEntry('show_chart', Icons.show_chart),
          IconEntry('analytics', Icons.analytics),
          IconEntry('paid', Icons.paid),
          IconEntry('money', Icons.attach_money),
          IconEntry('currency_exchange', Icons.currency_exchange),
          IconEntry('credit_card', Icons.credit_card),
          IconEntry('payment', Icons.payment),
          IconEntry('receipt_long', Icons.receipt_long),
          IconEntry('request_quote', Icons.request_quote),
          IconEntry('monetization_on', Icons.monetization_on),
          IconEntry('price_change', Icons.price_change),
          IconEntry('euro', Icons.euro_symbol),
          IconEntry('yen', Icons.currency_yen),
        ]),
        IconGroupData('奖励礼品', [
          IconEntry('card_giftcard', Icons.card_giftcard),
          IconEntry('redeem', Icons.redeem),
          IconEntry('wallet', Icons.wallet),
          IconEntry('emoji_events', Icons.emoji_events),
          IconEntry('celebration', Icons.celebration),
          IconEntry('volunteer_activism', Icons.volunteer_activism),
          IconEntry('loyalty', Icons.loyalty),
          IconEntry('military_tech', Icons.military_tech),
          IconEntry('workspace_premium', Icons.workspace_premium),
          IconEntry('verified', Icons.verified),
          IconEntry('diamond', Icons.diamond),
          IconEntry('auto_awesome', Icons.auto_awesome),
          IconEntry('new_releases', Icons.new_releases),
          IconEntry('toll', Icons.toll),
          IconEntry('casino', Icons.casino),
          IconEntry('confirmation_number', Icons.confirmation_number),
        ]),
        IconGroupData('投资收益', [
          IconEntry('apartment', Icons.apartment),
          IconEntry('real_estate_agent', Icons.home_work),
          IconEntry('home', Icons.home),
          IconEntry('house', Icons.house),
          IconEntry('store', Icons.store),
          IconEntry('storefront', Icons.storefront),
          IconEntry('factory', Icons.factory),
          IconEntry('agriculture', Icons.agriculture),
          IconEntry('energy_savings_leaf', Icons.eco),
          IconEntry('solar_power', Icons.solar_power),
          IconEntry('oil_barrel', Icons.propane_tank),
          IconEntry('local_gas_station', Icons.local_gas_station),
          IconEntry('electric_bolt', Icons.electric_bolt),
          IconEntry('water_drop', Icons.water_drop),
        ]),
        IconGroupData('其他收入', [
          IconEntry('handshake', Icons.handshake),
          IconEntry('schedule', Icons.schedule),
          IconEntry('undo', Icons.undo),
          IconEntry('refresh', Icons.refresh),
          IconEntry('autorenew', Icons.autorenew),
          IconEntry('update', Icons.update),
          IconEntry('sync', Icons.sync),
          IconEntry('published_with_changes', Icons.published_with_changes),
          IconEntry('swap_horiz', Icons.swap_horiz),
          IconEntry('compare_arrows', Icons.compare_arrows),
          IconEntry('call_received', Icons.call_received),
          IconEntry('input', Icons.input),
          IconEntry('move_down', Icons.move_down),
          IconEntry('south', Icons.south),
          IconEntry('call_made', Icons.call_made),
        ]),
      ];
    }
  }
}

class IconGroupData {
  final String title;
  final List<IconEntry> icons;

  const IconGroupData(this.title, this.icons);
}

class IconEntry {
  final String key;
  final IconData iconData;

  const IconEntry(this.key, this.iconData);
}
