import 'package:drama_tracker/screens/account_page.dart';
import 'package:drama_tracker/screens/heat_ranking_page.dart';
import 'package:drama_tracker/screens/home_calendar_page.dart';
import 'package:drama_tracker/screens/my_list_page.dart';
import 'package:drama_tracker/screens/search_page.dart';
import 'package:flutter/material.dart';

class AppShellPage extends StatefulWidget {
  const AppShellPage({
    super.key,
    required this.onLogout,
  });

  final VoidCallback onLogout;

  @override
  State<AppShellPage> createState() => _AppShellPageState();
}

class _AppShellPageState extends State<AppShellPage> {
  int _index = 0;

  Widget _navIcon(String assetName, {bool selected = false}) {
    final image = Image.asset(
      'assets/icons/$assetName',
      fit: BoxFit.cover,
      filterQuality: FilterQuality.high,
    );
    final content = selected
        ? image
        : ColorFiltered(
            colorFilter: const ColorFilter.mode(
              Color(0xFF9BB8FF),
              BlendMode.modulate,
            ),
            child: Opacity(
              opacity: 0.84,
              child: image,
            ),
          );
    return SizedBox(
      width: selected ? 34 : 31,
      height: selected ? 34 : 31,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: content,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      const HomeCalendarPage(),
      const HeatRankingPage(),
      const SearchPage(),
      MyListPage(
        onGoHome: () {
          setState(() {
            _index = 0;
          });
        },
      ),
      AccountPage(onLogout: widget.onLogout),
    ];
    final indexedPages = List<Widget>.generate(
      pages.length,
      (i) => HeroMode(
        enabled: _index == i,
        child: pages[i],
      ),
    );
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: indexedPages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        indicatorColor: Colors.transparent,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle?>((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              color: Color(0xFF00BFFF),
              fontWeight: FontWeight.w700,
            );
          }
          return const TextStyle(
            color: Color(0xFF9BB8FF),
            fontWeight: FontWeight.w600,
          );
        }),
        destinations: [
          NavigationDestination(
            icon: _navIcon('home.png'),
            selectedIcon: _navIcon('home.png', selected: true),
            label: '时间表',
          ),
          NavigationDestination(
            icon: _navIcon('ranking.png'),
            selectedIcon: _navIcon('ranking.png', selected: true),
            label: '热度榜',
          ),
          NavigationDestination(
            icon: _navIcon('search.png'),
            selectedIcon: _navIcon('search.png', selected: true),
            label: '搜索',
          ),
          NavigationDestination(
            icon: _navIcon('watchlist.png'),
            selectedIcon: _navIcon('watchlist.png', selected: true),
            label: '我的追番',
          ),
          NavigationDestination(
            icon: _navIcon('profile.png'),
            selectedIcon: _navIcon('profile.png', selected: true),
            label: '账号',
          ),
        ],
        onDestinationSelected: (index) {
          setState(() {
            _index = index;
          });
        },
      ),
    );
  }
}
