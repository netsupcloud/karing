// ignore_for_file: use_build_context_synchronously, empty_catches, unused_catch_stack, unused_catch_stack, duplicate_ignore

import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:contextmenu/contextmenu.dart';
import 'package:flutter/material.dart';
import 'package:karing/app/local_services/vpn_service.dart';
import 'package:karing/app/modules/biz.dart';
import 'package:karing/app/modules/server_manager.dart';
import 'package:karing/app/modules/setting_manager.dart';
import 'package:karing/app/runtime/return_result.dart';
import 'package:karing/app/utils/log.dart';
import 'package:karing/app/utils/network_utils.dart';
import 'package:karing/app/utils/proxy_conf_utils.dart';
import 'package:karing/app/utils/singbox_config_builder.dart';
import 'package:karing/i18n/strings.g.dart';
import 'package:karing/screens/common_widget.dart';
import 'package:karing/screens/dialog_utils.dart';
import 'package:karing/screens/group_item.dart';
import 'package:karing/screens/group_screen.dart';
import 'package:karing/screens/listview_multi_parts_builder.dart';
import 'package:karing/screens/server_select_keywords_screen.dart';
import 'package:karing/screens/theme_config.dart';
import 'package:karing/screens/theme_define.dart';
import 'package:karing/screens/widgets/framework.dart';
import 'package:tuple/tuple.dart';

class ServerSelectScreenSingleSelectedOption {
  final ProxyConfig selectedServer;
  final bool selectedServerInvalid;

  final bool showNone;
  final bool showCurrentSelect;
  final bool showAutoSelect;
  final bool showDirect;
  final bool showBlock;

  final bool showUrltestGroup;

  final bool showTranffic;
  final bool showUpdate;

  final bool showFav;
  final bool showRecommend;
  final bool showRecent;

  const ServerSelectScreenSingleSelectedOption({
    required this.selectedServer,
    this.selectedServerInvalid = false,
    this.showNone = false,
    this.showCurrentSelect = false,
    this.showAutoSelect = true,
    this.showDirect = false,
    this.showBlock = false,
    this.showUrltestGroup = false,
    this.showTranffic = true,
    this.showUpdate = true,
    this.showFav = true,
    this.showRecommend = true,
    this.showRecent = true,
  });
}

class ServerSelectScreenMultiSelectedOption {
  final List<ProxyConfig> selectedServers;
  final bool showSearchKeywords;
  List<String> searchKeywords;
  ServerSelectScreenMultiSelectedOption(
      {required this.selectedServers,
      this.showSearchKeywords = false,
      this.searchKeywords = const []}) {
    searchKeywords = searchKeywords.toList();
  }
}

class ServerSelectScreen extends LasyRenderingStatefulWidget {
  static RouteSettings routSettings() {
    return const RouteSettings(name: "ServerSelectScreen");
  }

  final String? title;
  final ServerSelectScreenSingleSelectedOption? singleSelect;
  final ServerSelectScreenMultiSelectedOption? multiSelect;
  final bool showLantencyTest;

  const ServerSelectScreen({
    super.key,
    this.title,
    required this.singleSelect,
    required this.multiSelect,
    this.showLantencyTest = true,
  });

  @override
  State<ServerSelectScreen> createState() => _ServerSelectScreenState();
}

class _ServerSelectScreenState extends LasyRenderingState<ServerSelectScreen> {
  static final Set<String> _expandGroup = {};
  final _searchController = TextEditingController();
  String _searchText = "";

  final Map<String, ProxyConfig> _allOutboundTagMap = {};
  List<SingboxOutboundUrltest> _urltests = [];
  final List<ListViewMultiPartsItem> _listViewParts = [];
  final List<ProxyConfig> _recommend = [];
  Timer? _timer;
  bool _rePaint = false;
  TapDownDetails _tapDownDetails = TapDownDetails();
  @override
  void initState() {
    ServerConfigGroupItem item = ServerManager.getCustomGroup();
    item.remark = t.custom;

    ServerDiversionGroupItem? itemDiversion =
        ServerManager.getDiversionCustomGroup();

    itemDiversion.remark = t.custom;

    _loadRecommend();
    _buildData();

    ServerManager.onTestLatency(hashCode,
        (String groupid, String tag, bool start, bool finish) {
      if (!mounted) {
        return;
      }
      if (finish) {
        _loadRecommend();
      }
      if (start || finish) {
        _buildData();
      }

      _rePaint = true;
    });
    ServerManager.onLatencyHistoryUpdated(hashCode, () {
      if (!mounted) {
        return;
      }

      _loadRecommend();
      _buildData();

      setState(() {});
    });
    ServerManager.onAddConfig((ServerConfigGroupItem item) async {
      if (!mounted) {
        return;
      }
      _loadRecommend();
      _buildData();
      setState(() {});
    });
    ServerManager.onRemoveConfig(
        (String groupid, bool enable, bool hasDeviersionGroup) async {
      if (!enable) {
        return;
      }
      if (!mounted) {
        return;
      }
      _loadRecommend();
      _buildData();
      setState(() {});
    });

    _timer ??= Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (_rePaint) {
        _rePaint = false;
        setState(() {});
      }
    });

    super.initState();
  }

  @override
  void dispose() {
    _listViewParts.clear();
    _timer?.cancel();
    _timer = null;
    ServerManager.onTestLatencyRemove(hashCode);
    ServerManager.onLatencyHistoryUpdatedRemove(hashCode);
    super.dispose();
    ServerManager.saveUse();
  }

  Future<bool> startVPN() async {
    return await Biz.startVPN(context, true, "ServerSelectScreen");
  }

  void _loadRecommend() {
    _recommend.clear();
    if (widget.singleSelect == null) {
      return;
    }
    if (!widget.singleSelect!.showRecommend) {
      return;
    }
    var servers = SplayTreeMap();
    for (var item in ServerManager.getConfig().items) {
      if (!item.enable) {
        continue;
      }
      for (var server in item.servers) {
        int? value = int.tryParse(server.latency);
        if (value != null) {
          servers[value] = server;
        }
      }
    }
    var use = ServerManager.getUse();
    for (var value in servers.values) {
      if (_recommend.length >= 3) {
        break;
      }
      String disableKey = ServerUse.getDisableKey(value);
      bool disabled = use.disable.contains(disableKey);
      if (disabled) {
        continue;
      }
      _recommend.add(value);
    }
  }

  _loadSearch(String? textVal) {
    _searchText = (textVal ?? "").toLowerCase();
    _buildData();
    setState(() {});
  }

  _clearSearch() {
    _searchController.clear();
    _searchText = "";
    _buildData();
    setState(() {});
  }

  _pushSearchSelect() async {
    String? searchText = await Navigator.push(
        context,
        MaterialPageRoute(
            settings: ServerSelectKeywordsScreen.routSettings(),
            builder: (context) => const ServerSelectKeywordsScreen()));
    if (searchText == null) {
      _buildData();
      setState(() {});
      return;
    }
    _searchText = searchText;
    _searchController.value = _searchController.value.copyWith(
      text: _searchText,
    );
    _buildData();
    setState(() {});
  }

  void _buildData() {
    RegExp? searchTextReg;
    try {
      if (_searchText.isNotEmpty) {
        searchTextReg = RegExp(_searchText, caseSensitive: false);
      }
    } catch (err, stacktrace) {}

    _listViewParts.clear();
    {
      ListViewMultiPartsItem item = ListViewMultiPartsItem();
      item.creator = (data, index, bindNO) {
        return createSearch();
      };
      _listViewParts.add(item);
    }
    {
      ListViewMultiPartsItem item = ListViewMultiPartsItem();
      item.creator = (data, index, bindNO) {
        return const SizedBox(
          height: 10,
        );
      };
      _listViewParts.add(item);
    }

    if (widget.singleSelect != null) {
      if (widget.singleSelect!.showNone) {
        ListViewMultiPartsItem item = ListViewMultiPartsItem();
        item.data = ServerManager.getNone();
        item.creator = (data, index, bindNO) {
          final tcontext = Translations.of(context);
          return createServerFake(data, tcontext.none, "");
        };
        _listViewParts.add(item);
      }
      if (widget.singleSelect!.showCurrentSelect) {
        ListViewMultiPartsItem item = ListViewMultiPartsItem();
        item.data = ServerManager.getByCurrentSelected();
        item.creator = (data, index, bindNO) {
          final tcontext = Translations.of(context);
          return createServerFake(
              data, tcontext.outboundActionCurrentSelected, "");
        };
        _listViewParts.add(item);
      }
      if (widget.singleSelect!.showAutoSelect) {
        ListViewMultiPartsItem item = ListViewMultiPartsItem();
        item.data = ServerManager.getUrltest();
        item.creator = (data, index, bindNO) {
          final tcontext = Translations.of(context);
          return createServerFake(data, tcontext.outboundActionUrltest,
              tcontext.ServerSelectScreen.autoSelectServer);
        };
        _listViewParts.add(item);
      }
      if (widget.singleSelect!.showDirect) {
        ListViewMultiPartsItem item = ListViewMultiPartsItem();
        item.data = ServerManager.getDirect();
        item.creator = (data, index, bindNO) {
          final tcontext = Translations.of(context);
          return createServerFake(data, tcontext.outboundActionDirect, "");
        };
        _listViewParts.add(item);
      }
      if (widget.singleSelect!.showBlock) {
        ListViewMultiPartsItem item = ListViewMultiPartsItem();
        item.data = ServerManager.getBlock();
        item.creator = (data, index, bindNO) {
          final tcontext = Translations.of(context);
          return createServerFake(data, tcontext.outboundActionBlock, "");
        };
        _listViewParts.add(item);
      }
      if (_searchText.isEmpty) {
        if (widget.singleSelect!.showRecommend) {
          if (!SettingManager.getConfig().uiScreen.selectServerHideRecommand) {
            if (_recommend.isNotEmpty) {
              ListViewMultiPartsItem item = ListViewMultiPartsItem();
              item.data = null;
              item.creator = (data, index, bindIndexv) {
                final tcontext = Translations.of(context);
                return createGroupSimple(
                    tcontext.recommended, null, null, null);
              };
              _listViewParts.add(item);
              for (int i = 0; i < _recommend.length; ++i) {
                ListViewMultiPartsItem item = ListViewMultiPartsItem();
                item.bindNO = i + 1;
                item.data = _recommend[i];
                item.creator = (data, index, bindNO) {
                  return createServer(data, bindNO!);
                };
                _listViewParts.add(item);
              }
            }
          }
        }
        var use = ServerManager.getUse();
        if (widget.singleSelect!.showRecent) {
          if (!SettingManager.getConfig().uiScreen.selectServerHideRecent) {
            if (use.recent.isNotEmpty) {
              ListViewMultiPartsItem item = ListViewMultiPartsItem();
              item.data = null;
              item.creator = (data, index, bindNO) {
                final tcontext = Translations.of(context);
                return createGroupSimple(tcontext.ServerSelectScreen.recentUse,
                    Icons.remove_circle_outlined, Colors.red, () {
                  ServerManager.clearRecent();
                  _buildData();
                  setState(() {});
                });
              };
              _listViewParts.add(item);

              for (int i = 0; i < use.recent.length; ++i) {
                ServerConfigGroupItem? group =
                    ServerManager.getByGroupId(use.recent[i].groupid);
                if (group == null || !group.enable) {
                  continue;
                }
                ProxyConfig? server = group.getByTag(use.recent[i].tag);
                if (server == null) {
                  continue;
                }
                ListViewMultiPartsItem item = ListViewMultiPartsItem();
                item.bindNO = i + 1;
                item.data = server;
                item.creator = (data, index, bindNO) {
                  return createServer(data, bindNO!);
                };
                _listViewParts.add(item);
              }
            }
          }
        }
        if (widget.singleSelect!.showFav) {
          if (!SettingManager.getConfig().uiScreen.selectServerHideFav) {
            if (use.fav.isNotEmpty) {
              ListViewMultiPartsItem item = ListViewMultiPartsItem();
              item.data = null;
              item.creator = (data, index, bindNO) {
                final tcontext = Translations.of(context);
                return createGroupSimple(tcontext.ServerSelectScreen.myFav,
                    Icons.network_ping_outlined, null, () async {
                  if (!await startVPN()) {
                    return;
                  }
                  for (int i = 0; i < use.fav.length; ++i) {
                    ServerConfigGroupItem? group =
                        ServerManager.getByGroupId(use.fav[i].groupid);
                    if (group == null || !group.enable) {
                      continue;
                    }
                    ProxyConfig? server = group.getByTag(use.fav[i].tag);
                    if (server == null) {
                      continue;
                    }
                    ServerManager.testOutboundLatencyForServer(
                        server.tag, server.groupid);
                  }
                });
              };
              _listViewParts.add(item);

              for (int i = 0; i < use.fav.length; ++i) {
                ServerConfigGroupItem? group =
                    ServerManager.getByGroupId(use.fav[i].groupid);
                if (group == null || !group.enable) {
                  continue;
                }
                ProxyConfig? server = group.getByTag(use.fav[i].tag);
                if (server == null) {
                  continue;
                }

                ListViewMultiPartsItem item = ListViewMultiPartsItem();
                item.bindNO = i + 1;
                item.data = server;
                item.creator = (data, index, bindNO) {
                  return createServer(data, bindNO!);
                };
                _listViewParts.add(item);
              }
            }
          }
        }
      }
    }
    if (widget.multiSelect != null &&
        widget.multiSelect!.showSearchKeywords &&
        ServerManager.getUse().serverSelectSearchSelect.isNotEmpty) {
      ListViewMultiPartsItem item = ListViewMultiPartsItem();
      item.data = null;
      item.creator = (data, index, bindNO) {
        final tcontext = Translations.of(context);
        return createGroupSimple(tcontext.candidateWord, null, null, null);
      };
      _listViewParts.add(item);

      for (var keyword in ServerManager.getUse().serverSelectSearchSelect) {
        ListViewMultiPartsItem item = ListViewMultiPartsItem();
        item.data = null;
        item.creator = (data, index, bindNO) {
          return createSearchKeywords(keyword);
        };
        _listViewParts.add(item);
      }
    }

    for (var group in ServerManager.getConfig().items) {
      if (!group.enable) {
        _expandGroup.remove(group.groupid);
        continue;
      }
      if (group.groupid != ServerManager.getCustomGroupId()) {
        if (group.servers.isEmpty) {
          _expandGroup.remove(group.groupid);
          continue;
        }
      }

      if (group.groupid == ServerManager.getCustomGroupId()) {
        if (widget.multiSelect != null ||
            widget.singleSelect == null ||
            !widget.singleSelect!.showUrltestGroup) {
          continue;
        }

        if (_allOutboundTagMap.isEmpty && _urltests.isEmpty) {
          Set<String> allOutboundsTags = {};
          List<ProxyConfig> allOutboundProxys = [];
          VPNService.getOutboundsWithoutUrltest(
              allOutboundsTags, allOutboundProxys, null, null);
          for (var proxy in allOutboundProxys) {
            _allOutboundTagMap[proxy.tag] = proxy;
          }
          _urltests = VPNService.getUrltests(allOutboundsTags,
              uniTag: false, includeEmpty: true);
        }

        ListViewMultiPartsItem item = ListViewMultiPartsItem();
        item.creator = (data, index, bindNO) {
          final tcontext = Translations.of(context);
          return createGroupProfile(group, false,
              itemName: tcontext.urlTestCustomGroup,
              replaceCount: _urltests.length);
        };
        _listViewParts.add(item);

        if (_searchText.isEmpty) {
          if (!_expandGroup.contains(group.groupid)) {
            continue;
          }
        }
        int count = 1;
        String errMessage = "";
        for (var urltest in _urltests) {
          try {
            if (_searchText.isEmpty ||
                (_searchText.isNotEmpty &&
                    (urltest.tag.toLowerCase().contains(_searchText) ||
                        kOutboundTypeUrltest.contains(_searchText) ||
                        (searchTextReg != null &&
                            searchTextReg.hasMatch(urltest.tag))))) {
              ListViewMultiPartsItem item = ListViewMultiPartsItem();
              item.data = urltest;
              item.bindNO = count++;
              item.creator = (data, index, bindNO) {
                ProxyConfig server =
                    ServerManager.getUrltest(tag: item.data.tag);
                int avaliableCount = 0;
                const int kMaxLatency = 10000;
                int latency = kMaxLatency;
                for (var tag in item.data.outbounds) {
                  var proxy = _allOutboundTagMap[tag];
                  if (proxy != null && proxy.latency.isNotEmpty) {
                    int? platency = int.tryParse(proxy.latency);
                    if (platency != null) {
                      avaliableCount += 1;
                      if (latency > platency) {
                        latency = platency;
                      }
                    }
                  }
                }
                if (latency != kMaxLatency) {
                  server.latency = latency.toString();
                }
                String count = "$avaliableCount/${item.data.outbounds.length}";
                return createServer(server, bindNO!,
                    count: count, showFav: false);
              };
              _listViewParts.add(item);
            }
          } catch (err, stacktrace) {
            errMessage = err.toString();
          }
        }
        if (errMessage.isNotEmpty) {
          Log.w("ServerSelectScreen $errMessage");
        }
        continue;
      }

      ListViewMultiPartsItem item = ListViewMultiPartsItem();
      item.data = group;
      item.creator = (data, index, bindNO) {
        return createGroupProfile(group, true);
      };
      _listViewParts.add(item);

      if (_searchText.isEmpty) {
        if (!_expandGroup.contains(group.groupid)) {
          continue;
        }
      }
      /*Set<String> detours = {};
      for (int i = 0; i < group.servers.length; ++i) {
        String? detour = group.servers[i].raw["detour"];
        if (detour != null && detour.isNotEmpty) {
          detours.add(detour);
        }
      }*/
      List<ProxyConfig> servers = [];
      if (group.testLatency.isNotEmpty) {
        servers = group.servers;
      } else {
        List<ProxyConfig> serversLatency = [];
        List<ProxyConfig> serversLatencyEmpty = [];
        List<ProxyConfig> serversLatencyError = [];
        for (int i = 0; i < group.servers.length; ++i) {
          var server = group.servers[i];
          //if (detours.contains(server.tag)) {
          //   continue;
          // }

          if (SettingManager.getConfig()
              .uiScreen
              .hideInvalidServerSelectServer) {
            if (server.latency.isNotEmpty) {
              int? value = int.tryParse(group.servers[i].latency);
              if (value == null) {
                continue;
              }
            }
          }
          if (SettingManager.getConfig().uiScreen.sortServerSelectServer) {
            if (server.latency.isEmpty) {
              serversLatencyEmpty.add(server);
            } else {
              if (null == int.tryParse(server.latency)) {
                serversLatencyError.add(server);
              } else {
                serversLatency.add(server);
              }
            }
          } else {
            servers.add(server);
          }
        }
        if (SettingManager.getConfig().uiScreen.sortServerSelectServer) {
          serversLatency.sort((a, b) {
            return int.parse(a.latency) - int.parse(b.latency);
          });
          servers.addAll(serversLatency);
          servers.addAll(serversLatencyEmpty);
          servers.addAll(serversLatencyError);
        }
      }
      List<ProxyConfig> searchServers =
          ServerManager.searchIn(servers, _searchText);

      for (int i = 0; i < searchServers.length; ++i) {
        ListViewMultiPartsItem item = ListViewMultiPartsItem();
        item.bindNO = i + 1;
        item.data = searchServers[i];
        item.creator = (data, index, bindNO) {
          return createServer(data, bindNO!);
        };
        _listViewParts.add(item);
      }
    }
  }

  Container createSearchKeywords(String keyword) {
    Size windowSize = MediaQuery.of(context).size;
    const double padding = 10;
    const double leftWidth = 30.0;

    double centerWidth = windowSize.width - leftWidth - padding * 2;
    return Container(
      margin: const EdgeInsets.only(bottom: 1),
      child: Material(
        borderRadius: ThemeDefine.kBorderRadius,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: padding,
          ),
          width: double.infinity,
          height: ThemeConfig.kListItemHeight,
          child: Row(
            children: [
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: leftWidth,
                        height: ThemeConfig.kListItemHeight,
                        child: Checkbox(
                          tristate: true,
                          value: widget.multiSelect!.searchKeywords
                              .contains(keyword),
                          onChanged: (bool? value) {
                            if (value == true) {
                              widget.multiSelect!.searchKeywords.add(keyword);
                            } else {
                              widget.multiSelect!.searchKeywords
                                  .remove(keyword);
                            }
                            setState(() {});
                          },
                        ),
                      ),
                      SizedBox(
                        width: centerWidth,
                        child: Text(
                          keyword,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: ThemeConfig.kFontSizeListSubItem,
                          ),
                        ),
                      ),
                    ],
                  )
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Row createGroupTitle(ServerConfigGroupItem item, bool showTestLatency,
      {String itemName = "", int? replaceCount}) {
    itemName = itemName.isNotEmpty ? itemName : item.remark;
    final tcontext = Translations.of(context);
    Size windowSize = MediaQuery.of(context).size;
    int count =
        ServerManager.getTestOutboundServerLatencyTestingCount(item.groupid) +
            item.testLatency.length;
    const double leftWidth = 5;
    const double rightWidth = 26 + 26 + 26 + 15 + 10;

    double centerWidth = windowSize.width - leftWidth - rightWidth;
    bool groupChecked = false;
    if (widget.multiSelect != null) {
      groupChecked = widget.multiSelect!.selectedServers
          .toSet()
          .intersection(item.servers.toSet())
          .isNotEmpty;
    }

    return Row(
      children: [
        const SizedBox(
          width: 5,
        ),
        SizedBox(
          height: 40,
          width: centerWidth,
          child: InkWell(
            onTap: () async {
              onTapGroupTitle(item.groupid);
            },
            child: Row(children: [
              widget.singleSelect != null
                  ? const SizedBox.shrink()
                  : Checkbox(
                      tristate: true,
                      value: groupChecked,
                      onChanged: (bool? value) {
                        if (value == true) {
                          if (_searchText.isEmpty) {
                            for (var server in item.servers) {
                              if (server.latency.isEmpty ||
                                  int.tryParse(server.latency) != null) {
                                widget.multiSelect!.selectedServers.add(server);
                              }
                            }
                          } else {
                            for (var server in item.servers) {
                              widget.multiSelect!.selectedServers
                                  .remove(server);
                            }
                            List<ProxyConfig> searchServers =
                                ServerManager.searchIn(
                                    item.servers, _searchText);
                            for (var server in searchServers) {
                              widget.multiSelect!.selectedServers.add(server);
                            }
                          }
                        } else {
                          for (var server in item.servers) {
                            widget.multiSelect!.selectedServers.remove(server);
                          }
                        }
                        setState(() {});
                      },
                    ),
              Icon(
                _expandGroup.contains(item.groupid)
                    ? Icons.keyboard_arrow_up_outlined
                    : Icons.keyboard_arrow_down_outlined,
                size: 26,
              ),
              SizedBox(
                width: centerWidth - 2 * 2 - 26,
                child: Text(
                  replaceCount == null
                      ? "$itemName[${item.servers.length}]"
                      : "$itemName[$replaceCount]",
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: ThemeConfig.kFontSizeListItem,
                    fontWeight: ThemeConfig.kFontWeightListItem,
                  ),
                ),
              ),
            ]),
          ),
        ),
        const Spacer(),
        widget.singleSelect != null &&
                widget.singleSelect!.showUpdate &&
                item.isRemote()
            ? Row(
                children: [
                  InkWell(
                    onTap: () async {
                      ServerManager.reload(item.groupid).then((value) {
                        if (!mounted) {
                          return;
                        }
                        if (value != null) {
                          DialogUtils.showAlertDialog(
                              context, tcontext.updateFailed(p: value.message),
                              showCopy: true, showFAQ: true, withVersion: true);
                        }
                        if (!mounted) {
                          return;
                        }
                        _buildData();
                        setState(() {});
                      });
                      setState(() {});
                    },
                    child: ServerManager.isReloading(item.groupid)
                        ? const SizedBox(
                            height: 26,
                            width: 26,
                            child: RepaintBoundary(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : const Icon(
                            Icons.cloud_download_outlined,
                            size: 26,
                          ),
                  ),
                  const SizedBox(
                    width: 10,
                  ),
                ],
              )
            : const SizedBox.shrink(),
        const SizedBox(
          width: 5,
        ),
        showTestLatency
            ? ServerManager.isTestLatency(item.groupid)
                ? Stack(
                    children: [
                      const SizedBox(
                        height: 26,
                        width: 26,
                        child: RepaintBoundary(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        top: 6,
                        height: 20,
                        width: 26,
                        child: Text(
                          count.toString(),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: count > 999 ? 8 : 10,
                          ),
                        ),
                      )
                    ],
                  )
                : InkWell(
                    onTap: () async {
                      bool ok = await startVPN();
                      if (!ok) {
                        return;
                      }
                      ServerManager.testOutboundLatencyForGroup(item.groupid)
                          .then((err) {
                        if (err != null) {
                          if (mounted) {
                            setState(() {});

                            DialogUtils.showAlertDialog(context, err.message,
                                showCopy: true,
                                showFAQ: true,
                                withVersion: true);
                          }
                        }
                      });
                    },
                    child: const Icon(
                      Icons.network_ping_outlined,
                      size: 26,
                    ),
                  )
            : const SizedBox.shrink(),
        const SizedBox(
          width: 15,
        ),
      ],
    );
  }

  Column createGroupProfile(ServerConfigGroupItem item, bool showTestLatency,
      {String itemName = "", int? replaceCount}) {
    final tcontext = Translations.of(context);
    Size windowSize = MediaQuery.of(context).size;
    return Column(children: [
      Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const SizedBox(
            width: 5,
          ),
          createGroupTitle(item, showTestLatency,
              itemName: itemName, replaceCount: replaceCount),
          widget.singleSelect != null && widget.singleSelect!.showTranffic
              ? CommonWidget.createGroupTraffic(
                  context,
                  item.groupid,
                  false,
                  item.traffic,
                  10,
                  MainAxisAlignment.start,
                  windowSize.width,
                  (String groupId) {
                    setState(() {});
                  },
                  (String groupId, ReturnResult<SubscriptionTraffic> value) {
                    if (!mounted) {
                      return;
                    }
                    setState(() {});
                    if (value.error != null) {
                      if (value.error!.message.contains("405")) {
                        ServerManager.reload(item.groupid).then((value) {
                          if (!mounted) {
                            return;
                          }
                          setState(() {});
                          if (value != null) {
                            DialogUtils.showAlertDialog(context,
                                tcontext.updateFailed(p: value.message),
                                showCopy: true,
                                showFAQ: true,
                                withVersion: true);
                          }
                        });
                      } else {
                        DialogUtils.showAlertDialog(context,
                            tcontext.updateFailed(p: value.error!.message),
                            showCopy: true, showFAQ: true, withVersion: true);
                      }
                    }

                    setState(() {});
                  },
                )
              : const SizedBox.shrink()
        ],
      ),
      const SizedBox(
        height: 10,
      ),
    ]);
  }

  Column createGroupSimple(
      String remark, IconData? icon, Color? iconColor, Function? onIconTap) {
    Size windowSize = MediaQuery.of(context).size;
    return Column(children: [
      const SizedBox(
        height: 20,
      ),
      Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const SizedBox(
            width: 10,
          ),
          Row(
            children: [
              const SizedBox(
                width: 5,
              ),
              SizedBox(
                width: windowSize.width * 0.7,
                height: 40,
                child: Text(
                  remark,
                  style: const TextStyle(
                    fontSize: ThemeConfig.kFontSizeListItem,
                    fontWeight: ThemeConfig.kFontWeightListItem,
                  ),
                ),
              ),
              const Spacer(),
              onIconTap != null
                  ? InkWell(
                      onTap: () async {
                        onIconTap();
                      },
                      child: Icon(icon, size: 26, color: iconColor),
                    )
                  : const SizedBox.shrink(),
              const SizedBox(
                width: 15,
              ),
            ],
          ),
        ],
      ),
      const SizedBox(
        height: 10,
      ),
    ]);
  }

  Container createServer(ProxyConfig server, int index,
      {String? count, bool showFav = true}) {
    final tcontext = Translations.of(context);
    String disableKey = ServerUse.getDisableKey(server);
    var use = ServerManager.getUse();
    bool disabled = use.disable.contains(disableKey);

    ServerConfigGroupItem? item = ServerManager.getByGroupId(server.groupid);
    bool isTesting = ServerManager.isTestOutboundServerLatencying(server.tag);
    bool isWaitTesting =
        (item != null && item.testLatency.contains(server.tag));
    Size windowSize = MediaQuery.of(context).size;
    const double padding = 10;
    const double leftWidth = 30.0;
    const double rightWidth = 135.0;
    String tag = server.tag;

    if (server.groupid == ServerManager.getUrltestGroupId()) {
      tag = server.tag == kOutboundTagUrltest
          ? tcontext.outboundActionUrltest
          : server.tag;
    } else if (server.groupid == ServerManager.getDirectGroupId()) {
      tag = tcontext.outboundActionDirect;
    } else if (server.groupid == ServerManager.getBlockGroupId()) {
      tag = tcontext.outboundActionBlock;
    }
    bool isFav = false;
    for (var fav in ServerManager.getUse().fav) {
      if (fav.groupid == server.groupid && fav.tag == server.tag) {
        isFav = true;
        break;
      }
    }

    double centerWidth =
        windowSize.width - leftWidth - rightWidth - padding * 2;
    double tagWidth = centerWidth;
    if (count != null) {
      tagWidth = tagWidth - 60;
    }
    if (server.attach.isNotEmpty) {
      tagWidth = tagWidth - 30;
    }
    bool noFavGroup = server.groupid == ServerManager.getUrltestGroupId() ||
        server.groupid == ServerManager.getDirectGroupId() ||
        server.groupid == ServerManager.getBlockGroupId();
    late bool singleSelectCurrent;
    late bool singleSelectCurrentInvalid;
    if (widget.singleSelect != null) {
      singleSelectCurrent = server.isSame(widget.singleSelect!.selectedServer);
      singleSelectCurrentInvalid =
          singleSelectCurrent && widget.singleSelect!.selectedServerInvalid;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 1),
      child: Material(
        borderRadius: ThemeDefine.kBorderRadius,
        child: ContextMenuArea(
          builder: (context) =>
              getLongPressServerPopMenu(server, isTesting, isWaitTesting),
          child: InkWell(
            onTap: widget.singleSelect == null
                ? null
                : () async {
                    if (server.type != kOutboundTypeUrltest) {
                      if (disabled) {
                        await DialogUtils.showAlertDialog(context,
                            tcontext.ServerSelectScreen.selectDisabled);
                        return;
                      }
                      if (server.server == "127.0.0.1" ||
                          server.server == "localhost") {
                        await DialogUtils.showAlertDialog(
                            context,
                            tcontext.ServerSelectScreen.selectLocal(
                                p: server.server));
                      }
                      var settingConfig = SettingManager.getConfig();
                      if (settingConfig.ipStrategy.index <
                          IPStrategy.preferIPv4.index) {
                        if (NetworkUtils.isIpv6(server.server)) {
                          await DialogUtils.showAlertDialog(
                              context,
                              tcontext
                                  .ServerSelectScreen.selectRequireEnableIPv6);
                        }
                      }
                    }

                    Navigator.pop(context, server);
                  },
            onTapDown: (details) {
              _tapDownDetails = details;
            },
            onLongPress: (widget.singleSelect == null ||
                    server.type == kOutboundTypeUrltest)
                ? null
                : () async {
                    onLongPressServer(server, isTesting, isWaitTesting);
                  },
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: padding,
              ),
              color: singleSelectCurrent
                  ? ThemeDefine.kColorBlue
                  : disabled
                      ? Colors.grey
                      : null,
              width: double.infinity,
              height: ThemeConfig.kListItemHeight,
              child: Row(
                children: [
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          SizedBox(
                            width: leftWidth,
                            height: ThemeConfig.kListItemHeight,
                            child: widget.singleSelect != null
                                ? Row(children: [
                                    Expanded(
                                      child: Text(
                                        index.toString(),
                                        style: TextStyle(
                                          fontSize: 12,
                                        ),
                                      ),
                                    )
                                  ])
                                : Checkbox(
                                    tristate: true,
                                    value: widget.multiSelect!.selectedServers
                                        .contains(server),
                                    onChanged: (bool? value) {
                                      if (value == true) {
                                        widget.multiSelect!.selectedServers
                                            .add(server);
                                      } else {
                                        widget.multiSelect!.selectedServers
                                            .remove(server);
                                      }
                                      setState(() {});
                                    },
                                  ),
                          ),
                          SizedBox(
                            width: tagWidth,
                            child: Text(
                              tag,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 3,
                              style: TextStyle(
                                  fontSize: ThemeConfig.kFontSizeListSubItem,
                                  fontFamily:
                                      Platform.isWindows ? 'Emoji' : null,
                                  color: singleSelectCurrentInvalid
                                      ? Colors.red
                                      : null),
                            ),
                          ),
                          server.attach.isEmpty
                              ? const SizedBox.shrink()
                              : SizedBox(
                                  width: 30,
                                  child: Text(
                                    server.attach,
                                    style: const TextStyle(
                                      fontSize: 10,
                                    ),
                                  ),
                                ),
                          count != null
                              ? SizedBox(
                                  width: 60,
                                  child: Text(
                                    count,
                                    style: const TextStyle(
                                      fontSize:
                                          ThemeConfig.kFontSizeListSubItem,
                                    ),
                                  ),
                                )
                              : const SizedBox.shrink(),
                          Container(
                            alignment: Alignment.centerRight,
                            width: rightWidth,
                            child: Row(children: [
                              const SizedBox(
                                width: 5,
                              ),
                              SizedBox(
                                height: ThemeConfig.kListItemHeight,
                                child: InkWell(
                                  onTap: noFavGroup
                                      ? null
                                      : () {
                                          ServerManager.toggleFav(server);
                                          if (SettingManager.getConfig()
                                              .autoSelect
                                              .prioritizeMyFav) {
                                            ServerManager.setDirty(true);
                                          }
                                          _buildData();
                                          setState(() {});
                                        },
                                  child: Row(children: [
                                    !showFav || noFavGroup
                                        ? const SizedBox.shrink()
                                        : Container(
                                            decoration: const BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: Colors.orange),
                                            child: Container(
                                              width: 20,
                                              height: 20,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: Colors.white
                                                    .withOpacity(0.8),
                                              ),
                                              child: Icon(
                                                Icons.star_outlined,
                                                size: 20,
                                                color: isFav
                                                    ? Colors.orange
                                                    : Colors.white,
                                              ),
                                            ),
                                          ),
                                    const SizedBox(
                                      width: 2,
                                    ),
                                    SizedBox(
                                      width:
                                          !showFav || noFavGroup ? 45 + 20 : 45,
                                      child: Text(
                                        server.getShowType(),
                                        style: const TextStyle(
                                          fontSize:
                                              ThemeConfig.kFontSizeListSubItem,
                                        ),
                                      ),
                                    ),
                                  ]),
                                ),
                              ),
                              const SizedBox(
                                width: 2,
                              ),
                              CommonWidget.createLatencyWidget(
                                context,
                                ThemeConfig.kListItemHeight,
                                isTesting | isWaitTesting,
                                isTesting,
                                server.latency,
                                onTapLatencyReload: () async {
                                  if (!await startVPN()) {
                                    return;
                                  }
                                  ServerManager.testOutboundLatencyForServer(
                                          server.tag, server.groupid)
                                      .then((err) {
                                    if (err != null) {
                                      if (mounted) {
                                        setState(() {});

                                        DialogUtils.showAlertDialog(
                                            context, err.message,
                                            showCopy: true,
                                            showFAQ: true,
                                            withVersion: true);
                                      }
                                    }
                                  });
                                },
                              )
                            ]),
                          ),
                        ],
                      )
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Container createSearch() {
    final tcontext = Translations.of(context);
    return Container(
      margin: const EdgeInsets.only(
        top: 10,
      ),
      padding: const EdgeInsets.only(left: 15, right: 15),
      height: 44,
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: ThemeDefine.kBorderRadius,
      ),
      child: TextField(
        controller: _searchController,
        textInputAction: TextInputAction.done,
        onChanged: _loadSearch,
        cursorColor: Colors.black,
        decoration: InputDecoration(
          border: InputBorder.none,
          focusedBorder: InputBorder.none,
          prefixIcon: Icon(
            Icons.search_outlined,
            color: Colors.grey.shade400,
          ),
          hintText: tcontext.search,
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(
                    Icons.clear_outlined,
                    color: Colors.black,
                  ),
                  onPressed: _clearSearch,
                )
              : IconButton(
                  icon: const Icon(Icons.arrow_forward_ios_outlined,
                      color: Colors.black),
                  onPressed: _pushSearchSelect,
                ),
        ),
      ),
    );
  }

  Container createServerFake(ProxyConfig server, String name, String tip) {
    if (widget.singleSelect == null) {
      return Container();
    }

    Size windowSize = MediaQuery.of(context).size;
    return Container(
      margin: const EdgeInsets.only(bottom: 1),
      child: Material(
        color: server.isSame(widget.singleSelect!.selectedServer)
            ? ThemeDefine.kColorBlue
            : null,
        borderRadius: ThemeDefine.kBorderRadius,
        child: InkWell(
          onTap: () {
            Navigator.pop(context, server);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 10,
            ),
            width: double.infinity,
            height: ThemeConfig.kListItemHeight,
            child: Row(
              children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        tip.isNotEmpty
                            ? Tooltip(
                                message: tip,
                                child: InkWell(
                                  onTap: () {
                                    DialogUtils.showAlertDialog(context, tip);
                                  },
                                  child: const Icon(
                                    Icons.info_outlined,
                                    size: 20,
                                  ),
                                ))
                            : const SizedBox.shrink(),
                        tip.isNotEmpty
                            ? const SizedBox(
                                width: 10,
                              )
                            : const SizedBox.shrink(),
                        SizedBox(
                          width: windowSize.width * 0.47,
                          height: 45,
                          child: Row(children: [
                            Expanded(
                              child: Text(
                                name,
                                style: const TextStyle(
                                  fontSize: ThemeConfig.kFontSizeListSubItem,
                                ),
                              ),
                            ),
                          ]),
                        ),
                      ],
                    )
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tcontext = Translations.of(context);
    Size windowSize = MediaQuery.of(context).size;
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: Size.zero,
        child: AppBar(),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 20, 0, 0),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    InkWell(
                      onTap: () {
                        if (widget.singleSelect != null) {
                          Navigator.pop(
                              context, widget.singleSelect!.selectedServer);
                        } else if (widget.multiSelect != null) {
                          Navigator.pop(context);
                        } else {
                          Navigator.pop(context);
                        }
                      },
                      child: const SizedBox(
                        width: 50,
                        height: 30,
                        child: Icon(
                          Icons.arrow_back_ios_outlined,
                          size: 26,
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () {
                        onTapExpandAllGroup();
                      },
                      child: Row(children: [
                        Icon(
                          _expandGroup.isNotEmpty
                              ? Icons.keyboard_double_arrow_up_outlined
                              : Icons.keyboard_double_arrow_down_outlined,
                          size: 26,
                        ),
                        SizedBox(
                          width: windowSize.width - 50 * 3 - 26,
                          child: Text(
                            widget.title != null && widget.title!.isNotEmpty
                                ? widget.title!
                                : tcontext.ServerSelectScreen.title,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: ThemeConfig.kFontWeightTitle,
                                fontSize: ThemeConfig.kFontSizeTitle),
                          ),
                        ),
                      ]),
                    ),
                    Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          widget.multiSelect != null
                              ? InkWell(
                                  onTap: () => Navigator.pop(
                                      context,
                                      Tuple2(widget.multiSelect!.searchKeywords,
                                          widget.multiSelect!.selectedServers)),
                                  child: const SizedBox(
                                    width: 50,
                                    height: 30,
                                    child: Icon(
                                      Icons.done_outlined,
                                      size: 26,
                                    ),
                                  ),
                                )
                              : InkWell(
                                  onTap: () async {
                                    onTapTestOutboundLatencyAll();
                                  },
                                  child: const SizedBox(
                                      width: 50,
                                      height: 30,
                                      child: Icon(
                                        Icons.network_ping_outlined,
                                        size: 30,
                                      )),
                                ),
                          InkWell(
                            onTap: () async {
                              onTapSetting();
                            },
                            child: const SizedBox(
                              width: 50,
                              height: 30,
                              child: Icon(
                                Icons.settings_outlined,
                                size: 30,
                              ),
                            ),
                          ),
                        ])
                  ],
                ),
              ),
              const SizedBox(
                height: 10,
              ),
              Expanded(child: ListViewMultiPartsBuilder.build(_listViewParts)),
            ],
          ),
        ),
      ),
    );
  }

  void onTapExpandAllGroup() {
    if (_expandGroup.isNotEmpty) {
      _expandGroup.clear();
    } else {
      for (var item in ServerManager.getConfig().items) {
        if (!item.enable) {
          continue;
        }
        if (item.groupid == ServerManager.getCustomGroupId()) {
          if (widget.singleSelect != null) {
            if (widget.singleSelect!.showUrltestGroup) {
              _expandGroup.add(item.groupid);
            }
          }
        } else {
          _expandGroup.add(item.groupid);
        }
      }
    }

    _buildData();
    setState(() {});
  }

  void onTapSetting() async {
    final tcontext = Translations.of(context);
    Future<List<GroupItem>> getOptions(BuildContext context) async {
      var settingConfig = SettingManager.getConfig();
      List<GroupItemOptions> options = [];
      if (widget.singleSelect != null) {
        if (widget.singleSelect!.showRecommend) {
          options.add(GroupItemOptions(
              switchOptions: GroupItemSwitchOptions(
            name: tcontext.SettingsScreen.selectServerHideRecommand,
            switchValue: settingConfig.uiScreen.selectServerHideRecommand,
            onSwitch: (bool value) async {
              settingConfig.uiScreen.selectServerHideRecommand = value;
              setState(() {});
            },
          )));
        }
        if (widget.singleSelect!.showRecent) {
          options.add(GroupItemOptions(
              switchOptions: GroupItemSwitchOptions(
            name: tcontext.SettingsScreen.selectServerHideRecent,
            switchValue: settingConfig.uiScreen.selectServerHideRecent,
            onSwitch: (bool value) async {
              settingConfig.uiScreen.selectServerHideRecent = value;
              setState(() {});
            },
          )));
        }
        if (widget.singleSelect!.showFav) {
          options.add(GroupItemOptions(
              switchOptions: GroupItemSwitchOptions(
            name: tcontext.SettingsScreen.selectServerHideFav,
            switchValue: settingConfig.uiScreen.selectServerHideFav,
            onSwitch: (bool value) async {
              settingConfig.uiScreen.selectServerHideFav = value;
              setState(() {});
            },
          )));
        }
      }

      List<GroupItemOptions> options1 = [
        GroupItemOptions(
            switchOptions: GroupItemSwitchOptions(
                name: tcontext.SettingsScreen.hideInvalidServer,
                switchValue:
                    settingConfig.uiScreen.hideInvalidServerSelectServer,
                onSwitch: (bool value) async {
                  settingConfig.uiScreen.hideInvalidServerSelectServer = value;

                  setState(() {});
                })),
        GroupItemOptions(
            switchOptions: GroupItemSwitchOptions(
                name: tcontext.SettingsScreen.sortServer,
                switchValue: settingConfig.uiScreen.sortServerSelectServer,
                onSwitch: (bool value) async {
                  settingConfig.uiScreen.sortServerSelectServer = value;
                  setState(() {});
                })),
      ];
      if (options.isEmpty) {
        return [GroupItem(options: options1)];
      }
      return [GroupItem(options: options), GroupItem(options: options1)];
    }

    await Navigator.push(
        context,
        MaterialPageRoute(
            settings: GroupScreen.routSettings("ServerSelectScreen.setting"),
            builder: (context) => GroupScreen(
                  title: tcontext.setting,
                  getOptions: getOptions,
                )));
    _buildData();
    setState(() {});
    SettingManager.saveConfig();
  }

  void onTapTestOutboundLatencyAll() async {
    bool ok = await startVPN();
    if (!ok) {
      return;
    }
    for (var group in ServerManager.getConfig().items) {
      ServerManager.testOutboundLatencyForGroup(group.groupid);
    }
  }

  void onTapGroupTitle(String groupid) {
    if (_expandGroup.contains(groupid)) {
      _expandGroup.remove(groupid);
    } else {
      _expandGroup.add(groupid);
    }

    _buildData();
    setState(() {});
  }

  List<PopupMenuItem> getLongPressServerPopMenu(
      ProxyConfig server, bool isTesting, bool isWaitTesting) {
    if (!mounted) {
      return [];
    }
    ServerConfigGroupItem? item = ServerManager.getByGroupId(server.groupid);
    if (item == null) {
      return [];
    }
    final tcontext = Translations.of(context);
    String disableKey = ServerUse.getDisableKey(server);
    bool disabled = ServerManager.getUse().disable.contains(disableKey);
    String msg = disabled ? tcontext.enable : tcontext.disable;
    msg += "[${server.type};${server.server};${server.serverport}]";

    var items = [
      PopupMenuItem(
          value: 1,
          child: Text(msg),
          onTap: () {
            var use = ServerManager.getUse();
            if (disabled) {
              use.disable.remove(disableKey);
            } else {
              use.disable.add(disableKey);
            }
            ServerManager.setDirty(true);
            _loadRecommend();
            _buildData();
            setState(() {});
          }),
    ];

    return items;
  }

  void onLongPressServer(
      ProxyConfig server, bool isTesting, bool isWaitTesting) async {
    var items = getLongPressServerPopMenu(server, isTesting, isWaitTesting);
    var postion = RelativeRect.fromLTRB(
        _tapDownDetails.globalPosition.dx + 20,
        _tapDownDetails.globalPosition.dy - 50,
        MediaQuery.of(context).size.width - _tapDownDetails.globalPosition.dx,
        0);
    showMenu(context: context, position: postion, items: items);
  }
}
