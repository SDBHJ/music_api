import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:music_api/pages/preview_page.dart';
import 'package:provider/provider.dart';
import 'package:super_tooltip/super_tooltip.dart';

import '../../components/custom_drawer.dart';
import '../../components/custom_switch.dart';
import '../../components/home_components.dart';
import '../../providers/switch_state.dart';
import '../../utilities/color_scheme.dart';
import '../../utilities/text_theme.dart';


class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final Completer<NaverMapController> _controller = Completer();
  final ScrollController _scrollController = ScrollController();
  final _tooltipController = SuperTooltipController();
  final _textController = TextEditingController();
  NMarker? _userLocationMarker;
  late NaverMapController mapController;
  int markerCount = 0;
  int lineCount = 0;
  bool editMode = false;
  late NCameraPosition camera;
  int selectedIndex = 0;

  NCameraPosition initPosition = const NCameraPosition(
      target: NLatLng(36.10174928712425, 129.39070716683418), zoom: 15);

  late Position position;

  Set<NMarker> markers = {};
  Set<NPolylineOverlay> lineOverlays = {};

  // 선 그리기 전 선택되는 마커
  List<NLatLng> selectedMarkerCoords = [];

  // 권한 요청
  Future<bool> _determinePermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return Future.value(false);
    }
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return Future.value(false);
      }
    }
    if (permission == LocationPermission.deniedForever) {
      return Future.value(false);
    }
    return Future.value(true);
  }

  // GPS 정보 얻기
  Future<Position> _getPosition() async {
    return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best);
  }

  // GPS 정보 도로명 주소로 변환
  Future<String> _getAddress(double lat, double lon) async {
    // 네이버 API 키
    String clientId = 'oic87mpcyw';
    String clientSecret = 'ftEbewAoHtXhrpokEHAk7TUPAZzR1r4woeMja3hE';

    // 요청 URL 만들기
    String url =
        'https://naveropenapi.apigw.ntruss.com/map-reversegeocode/v2/gc?request=coordsToaddr&coords=$lon,$lat&sourcecrs=epsg:4326&output=json&orders=addr,admcode,roadaddr';

    // HTTP GET 요청 보내기
    var response = await http.get(Uri.parse(url), headers: {
      'X-NCP-APIGW-API-KEY-ID': clientId,
      'X-NCP-APIGW-API-KEY': clientSecret
    });

    // 응답 처리
    if (response.statusCode == 200) {
      var jsonResponse = json.decode(response.body);
      var address = jsonResponse['results'][0]['region']['area2']['name'] +
          ' ' +
          jsonResponse['results'][0]['region']['area3']['name'];
      return address;
    } else {
      return '주소 정보를 가져오는데 실패했습니다.';
    }
  }

  // 현재 위치로 이동
  void _updatePosition() async {
    camera = await mapController.getCameraPosition();
    position = await _getPosition();
    mapController.updateCamera(NCameraUpdate.withParams(
        target: NLatLng(position.latitude, position.longitude),
        zoom: camera.zoom));
    // _drawCircle(position);
  }

  // 현재 위치에 마커 찍기
  void _userLocation() {
    Geolocator.getPositionStream().listen((Position position) {
      if (_userLocationMarker == null) {
        // 초기 사용자 위치 마커를 생성합니다.
        _userLocationMarker = NMarker(
            id: 'user_location',
            position: NLatLng(position.latitude, position.longitude),
            icon: const NOverlayImage.fromAssetImage(
                'assets/images/my_location.png'), // 동그라미 이미지
            size: const Size(32, 32));
        setState(() {
          // 마커를 지도에 추가합니다.
          mapController.addOverlay(_userLocationMarker!);
        });
      } else {
        // 사용자 위치가 변경될 때마다 마커 위치를 업데이트합니다.
        setState(() {
          _userLocationMarker = NMarker(
            id: 'user_location',
            position: NLatLng(position.latitude, position.longitude),
            icon: const NOverlayImage.fromAssetImage(
                'assets/images/my_location.png'),
            size: const Size(32, 32), // 동그라미 이미지
          );
        });
      }
    });
  }

  // 마커 그리기 함수
  void drawMarker(NLatLng latLng) async {
    // 마커 생성
    final marker = NMarker(
      id: '$markerCount',
      position: NLatLng(latLng.latitude, latLng.longitude),
      icon: const NOverlayImage.fromAssetImage('assets/images/my_marker.png'),
      size: const Size(35, 35),
      anchor: const NPoint(0.5, 0.5),
    );
    // 마커 클릭 시 이벤트 설정
    marker.setOnTapListener((overlay) {
      setState(() {
        if (context.read<SwitchProvider>().switchMode) {
          selectedMarkerCoords.add(overlay.position);
          debugPrint("$selectedMarkerCoords");
          if (selectedMarkerCoords.length == 2) {
            drawPolyline();
          }
        }
      });
    });
    marker.setGlobalZIndex(200000);
    mapController.addOverlay(marker);
    setState(() {
      markers.add(marker);
      markerCount++;
    });
    debugPrint("${marker.info}");
  }

  // 선 그리기 함수
  void drawPolyline() {
    // 선 생성
    final polylineOverlay = NPolylineOverlay(
        id: '$lineCount',
        coords: List.from(selectedMarkerCoords),
        color: Colors.white,
        width: 3);
    // 선 클릭 시 이벤트 설정
    polylineOverlay.setOnTapListener((overlay) {
      if (context.read<SwitchProvider>().switchMode) {
        mapController.deleteOverlay(overlay.info);
        setState(() {
          lineOverlays.remove(polylineOverlay);
          lineCount--;
        });
      }
    });
    polylineOverlay.setGlobalZIndex(190000);
    mapController.addOverlay(polylineOverlay);
    setState(() {
      lineOverlays.add(polylineOverlay);
      lineCount++;
    });
    // 선 그린 후 선택된 마커들 삭제
    selectedMarkerCoords.clear();
  }

  // 이미지 저장
  void saveMapImage() async {
    try {
      // 현재 카메라 위치 저장
      camera = await mapController.getCameraPosition();
      camera = NCameraPosition(
          target: camera.target,
          zoom: camera.zoom - 0.15,
          bearing: camera.bearing);
      debugPrint("parent: ${await mapController.getContentBounds()}");
      String name = _textController.text;
      if (!mounted) return;
      Navigator.push(
          context,
          MaterialPageRoute(
              builder: (context) => PreviewPage(
                    markers: markers,
                    polylines: lineOverlays,
                    position: camera,
                    name: name,
                  )));
    } catch (e) {
      debugPrint('이미지 저장 중 오류 발생: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _determinePermission();
  }

  @override
  void dispose() {
    Geolocator.getPositionStream().listen((_) {}).cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    bool switchMode = Provider.of<SwitchProvider>(context).switchMode;
    return Scaffold(
      key: _scaffoldKey,
      endDrawer: const SizedBox(
        width: 240,
        child: CustomDrawer(),
      ),
      body: Stack(children: [
        Container(
          color: Colors.black,
          child: NaverMap(
            options: NaverMapViewOptions(
                initialCameraPosition: initPosition,
                mapType: NMapType.navi,
                nightModeEnable: true,
                indoorEnable: true,
                logoClickEnable: false,
                consumeSymbolTapEvents: false,
                pickTolerance: 10),
            // 지도 실행 시 이벤트
            onMapReady: (controller) async {
              mapController = controller;
              _controller.complete(controller);
              _userLocation();
            },
            // 지도 탭 이벤트
            onMapTapped: (point, latLng) async {
              drawMarker(latLng);
              debugPrint(await _getAddress(latLng.latitude, latLng.longitude));
            },
          ),
        ),
        // AppBar
        Align(
            alignment: Alignment.topCenter,
            child: Container(
              height: 160,
              color: Colors.transparent,
              padding: const EdgeInsets.only(top: 60),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const SizedBox(width: 25),
                      GestureDetector(
                          onTap: () {
                            if (!switchMode) {
                              context.read<SwitchProvider>().toggleMode();
                            } else {
                              showCupertinoDialog(
                                  context: context,
                                  builder: (BuildContext ctx) {
                                    return Theme(
                                      data: ThemeData.dark(),
                                      child: CupertinoAlertDialog(
                                        title: const Text("별 잇기를 그만하시겠어요?",
                                            style: regular17),
                                        actions: [
                                          CupertinoDialogAction(
                                              child: Text("계속하기",
                                                  style: regular17.copyWith(
                                                      color: AppColor.sub2)),
                                              onPressed: () {
                                                Navigator.pop(context);
                                              }),
                                          CupertinoDialogAction(
                                              child: Text("나가기",
                                                  style: regular17.copyWith(
                                                      color: AppColor.error)),
                                              onPressed: () {
                                                mapController.clearOverlays(
                                                    type: NOverlayType
                                                        .polylineOverlay);
                                                selectedMarkerCoords.clear();
                                                lineOverlays.clear();
                                                lineCount == 0;
                                                Navigator.pop(context);
                                                context
                                                    .read<SwitchProvider>()
                                                    .toggleMode();
                                              })
                                        ],
                                      ),
                                    );
                                  });
                            }
                          },
                          child: const CustomSwitch()),
                      const SizedBox(width: 65),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Image.asset("assets/images/logo.png",
                              width: 85, height: 35),
                          const SizedBox(width: 8),
                          switchMode
                              ? CustomTooltip(controller: _tooltipController)
                              : const SizedBox(width: 22)
                        ],
                      ),
                      const SizedBox(width: 70),
                      GestureDetector(
                          onTap: () =>
                              _scaffoldKey.currentState?.openEndDrawer(),
                          child: const Icon(Icons.menu,
                              color: AppColor.text, size: 22)),
                      const SizedBox(width: 25)
                    ],
                  ),
                  const SizedBox(height: 30),
                  // Chip들
                  Visibility(
                    visible: !switchMode,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 25),
                      child: SingleChildScrollView(
                        controller: _scrollController,
                        // physics: const ClampingScrollPhysics(),
                        scrollDirection: Axis.horizontal,
                        child: Row(
                            children: List.generate(6, (int index) {
                          if (index != 5) {
                            return Row(children: [
                              CustomChip(
                                  name: [
                                    '전체',
                                    '나',
                                    '메이트 전체',
                                    '메이트 1',
                                    '메이트 2',
                                    '메이트 3'
                                  ][index],
                                  isSelected: index == selectedIndex,
                                  function: () {
                                    setState(() {
                                      selectedIndex = index;
                                    });
                                  }),
                              const SizedBox(width: 7.2)
                            ]);
                          } else {
                            return CustomChip(
                                name: [
                                  '전체',
                                  '나',
                                  '메이트 전체',
                                  '메이트 1',
                                  '메이트 2',
                                  '메이트 3'
                                ][index],
                                isSelected: index == selectedIndex,
                                function: () {
                                  setState(() {
                                    selectedIndex = index;
                                  });
                                });
                          }
                        }).toList()),
                      ),
                    ),
                  ),
                ],
              ),
            )),

        // 현재 위치 버튼
        Visibility(
          visible: !switchMode,
          child: Positioned(
            top: 180,
            right: 30,
            child: LocationButton(goToLocation: _updatePosition),
          ),
        ),

        // FAB
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 60),
            child: switchMode
                ? (lineOverlays.isEmpty
                    ? const CompleteButtonDisable()
                    : CompleteButtonEnable(complete: saveMapImage))
                : PutStar(putMarker: _userLocation),
          ),
        ),
      ]),
    );
  }
}