import '../models/home_assistant_room.dart';
import 'i18n.dart';

const _roomTypeByIcon = <String, String>{
  'mdi:sofa-outline': 'living_room',
  'mdi:bed-outline': 'bedroom',
  'mdi:silverware-fork-knife': 'kitchen',
  'mdi:shower': 'bathroom',
  'mdi:desk': 'office',
  'mdi:garage': 'garage',
  'mdi:table-chair': 'dining_room',
  'mdi:baby-face-outline': 'kids_room',
  'mdi:door-open': 'entryway',
  'mdi:stairs': 'hallway',
  'mdi:washing-machine': 'laundry_room',
  'mdi:food-apple-outline': 'pantry',
  'mdi:balcony': 'balcony',
  'mdi:flower-outline': 'terrace',
  'mdi:greenhouse': 'garden',
  'mdi:home-floor-negative-1': 'basement',
  'mdi:tools': 'workshop',
};
final _iconByRoomType = {
  for (final entry in _roomTypeByIcon.entries) entry.value: entry.key,
};

String roomTypeForIcon(String icon) => _roomTypeByIcon[icon] ?? '';

String localizedRoomName(HomeAssistantRoom room) {
  final localizationIcon = _iconByRoomType[room.roomType] ?? room.icon;
  final values = switch (localizationIcon) {
    'mdi:sofa-outline' => (
        'Гостиная',
        'Куно комната',
        'Living room',
        'Кунак бүлмәсе'
      ),
    'mdi:bed-outline' => ('Спальня', 'Узон комната', 'Bedroom', 'Йокы бүлмәсе'),
    'mdi:silverware-fork-knife' => ('Кухня', 'Кухня', 'Kitchen', 'Аш бүлмәсе'),
    'mdi:shower' => ('Ванная', 'Миськон комната', 'Bathroom', 'Юыну бүлмәсе'),
    'mdi:desk' => ('Кабинет', 'Уж комната', 'Office', 'Эш бүлмәсе'),
    'mdi:garage' => ('Гараж', 'Гараж', 'Garage', 'Гараж'),
    'mdi:table-chair' => ('Столовая', 'Сиён комната', 'Dining room', 'Ашханә'),
    'mdi:baby-face-outline' => (
        'Детская',
        'Пиналъёс комната',
        'Kids room',
        'Балалар бүлмәсе'
      ),
    'mdi:door-open' => ('Прихожая', 'Азьпал', 'Entryway', 'Керү бүлмәсе'),
    'mdi:stairs' => ('Коридор', 'Коридор', 'Hallway', 'Коридор'),
    'mdi:washing-machine' => (
        'Прачечная',
        'Миськонни',
        'Laundry room',
        'Кер юу бүлмәсе'
      ),
    'mdi:food-apple-outline' => ('Кладовая', 'Келәт', 'Pantry', 'Келәт'),
    'mdi:balcony' => ('Балкон', 'Балкон', 'Balcony', 'Балкон'),
    'mdi:flower-outline' => ('Терраса', 'Терраса', 'Terrace', 'Терраса'),
    'mdi:greenhouse' => ('Сад', 'Бакча', 'Garden', 'Бакча'),
    'mdi:home-floor-negative-1' => ('Подвал', 'Улынъёс', 'Basement', 'Подвал'),
    'mdi:tools' => ('Мастерская', 'Ужьянни', 'Workshop', 'Остаханә'),
    _ => null,
  };
  if (values == null) return room.name;
  return I18n.t(values.$1, values.$2, values.$3, tt: values.$4);
}
