"""Project the maintained dining research (content/dining.json) into the place catalog."""


def dining_places(document):
    places = []
    for restaurant in document['restaurants']:
        duration = restaurant.get('durationMinutes', 120 if restaurant['type'] == 'restaurant' else 60)
        booking = restaurant['booking']
        places.append({
            'id': restaurant['id'], 'name': restaurant['name'], 'en': restaurant['en'],
            'zone': restaurant['zone'], 'kind': '餐饮', 'hours': duration / 60,
            'budget': 0, 'desc': restaurant['description'],
            'tip': '\n'.join(restaurant['tips']), 'travel': restaurant['address'],
            'rain': '下雨时先确认交通与店内候位安排。', 'food': '、'.join(restaurant['cuisines']),
            'link': booking['url'] or next((s['url'] for s in restaurant['sources']), ''),
            'opening': restaurant['hours'], 'price': '餐费见餐饮详情；不计入门票预算',
        })
    return places


def merge_dining_places(catalog, document):
    projected = {place['id']: place for place in dining_places(document)}
    places = [projected.pop(place['id'], place) for place in catalog['places']]
    return {**catalog, 'places': places + list(projected.values())}
