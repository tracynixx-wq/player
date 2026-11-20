import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

void main() => runApp(const PlayerApp());

const bg = Color(0xFF0B0A10);
const panel = Color(0xFF17151F);
const raised = Color(0xFF211D2B);
const violet = Color(0xFF9B7BFF);
const muted = Color(0xFF9A94A8);

class PlayerApp extends StatelessWidget {
  const PlayerApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'PLAYER — музыка',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bg,
      colorScheme: ColorScheme.fromSeed(seedColor: violet, brightness: Brightness.dark),
      useMaterial3: true,
    ),
    home: const PlayerHome(),
  );
}

class PlayerHome extends StatefulWidget {
  const PlayerHome({super.key});
  @override
  State<PlayerHome> createState() => _PlayerHomeState();
}

class _PlayerHomeState extends State<PlayerHome> {
  final AudioPlayer player = AudioPlayer();
  final TextEditingController spotify = TextEditingController();
  final List<PlatformFile> tracks = [];
  int current = -1;
  bool busy = false;
  bool shuffle = false;
  LoopMode repeat = LoopMode.off;
  String status = 'Добавьте аудиофайлы, чтобы начать слушать';
  PlatformFile? get active => current >= 0 && current < tracks.length ? tracks[current] : null;

  Future<void> pickFiles() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.audio, allowMultiple: true, withData: true);
      if (result == null || result.files.isEmpty) return;
      final start = tracks.length;
      setState(() { tracks.addAll(result.files); status = 'Добавлено файлов: ${result.files.length}'; });
      if (current == -1) await loadTrack(start);
    } catch (e) {
      message('Не удалось открыть файлы: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> loadTrack(int index) async {
    if (index < 0 || index >= tracks.length) return;
    final file = tracks[index];
    try {
      setState(() { current = index; status = 'Загружаю ${file.name}'; });
      if (!kIsWeb && file.path != null) {
        await player.setFilePath(file.path!);
      } else if (file.bytes != null) {
        await player.setAudioSource(AudioSource.uri(Uri.dataFromBytes(file.bytes!, mimeType: mime(file.name))));
      } else {
        throw Exception('Не удалось получить содержимое файла');
      }
      if (!mounted) return;
      setState(() => status = 'Сейчас играет');
      await player.play();
    } catch (e) {
      if (mounted) setState(() => status = 'Ошибка загрузки файла');
      message('Не удалось воспроизвести ${file.name}: $e');
    }
  }

  String mime(String name) {
    const types = {'mp3':'audio/mpeg','m4a':'audio/mp4','aac':'audio/aac','wav':'audio/wav','ogg':'audio/ogg','oga':'audio/ogg','opus':'audio/opus','flac':'audio/flac','webm':'audio/webm'};
    return types[name.split('.').last.toLowerCase()] ?? 'application/octet-stream';
  }

  Future<void> next() async {
    if (tracks.isEmpty) return;
    if (shuffle && tracks.length > 1) {
      final n = (current + 1 + DateTime.now().millisecond) % tracks.length;
      await loadTrack(n == current ? (n + 1) % tracks.length : n);
    } else if (current + 1 < tracks.length) {
      await loadTrack(current + 1);
    } else if (repeat == LoopMode.all) {
      await loadTrack(0);
    } else if (repeat == LoopMode.one) {
      await player.seek(Duration.zero);
      await player.play();
    }
  }

  Future<void> previous() async {
    if (current > 0) { await loadTrack(current - 1); } else { await player.seek(Duration.zero); }
  }

  void toggleRepeat() {
    setState(() => repeat = repeat == LoopMode.off ? LoopMode.all : repeat == LoopMode.all ? LoopMode.one : LoopMode.off);
    player.setLoopMode(repeat);
  }

  void checkSpotify() {
    final uri = Uri.tryParse(spotify.text.trim());
    final segments = uri?.pathSegments ?? const <String>[];
    final i = segments.indexOf('playlist');
    final valid = uri != null && (uri.host == 'open.spotify.com' || uri.host == 'www.spotify.com') &&
      i >= 0 && i + 1 < segments.length && RegExp(r'^[A-Za-z0-9]+$').hasMatch(segments[i + 1]);
    message(valid
      ? 'Ссылка распознана. Получение списка треков подключается отдельно через Spotify API.'
      : 'Вставьте корректную ссылку на плейлист Spotify.');
  }

  void message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(SnackBar(content: Text(value)));
  }

  String time(Duration d) => '${d.inMinutes.remainder(60).toString().padLeft(2,'0')}:${d.inSeconds.remainder(60).toString().padLeft(2,'0')}';

  @override
  void dispose() { spotify.dispose(); player.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(child: LayoutBuilder(builder: (context, box) => Column(children: [
      header(),
      Expanded(child: box.maxWidth >= 760 ? wideContent() : mobileContent()),
      playerBar(),
    ]))),
  );

  Widget header() => Padding(
    padding: const EdgeInsets.fromLTRB(22,18,22,14),
    child: Row(children: [
      Container(width:42,height:42,decoration:BoxDecoration(
        gradient: const LinearGradient(colors:[violet,Color(0xFF6545C6)]),
        borderRadius:BorderRadius.circular(14)),
        child: const Icon(Icons.graphic_eq_rounded,color:Colors.white)),
      const SizedBox(width:12),
      const Text('PLAYER',style:TextStyle(fontSize:19,fontWeight:FontWeight.w800,letterSpacing:2.2)),
      const Spacer(),
      Container(padding:const EdgeInsets.symmetric(horizontal:12,vertical:8),
        decoration:BoxDecoration(color:panel,borderRadius:BorderRadius.circular(30)),
        child:const Row(children:[Icon(Icons.circle,size:7,color:Color(0xFF73D6A0)),SizedBox(width:7),
          Text('ЛОКАЛЬНАЯ МУЗЫКА',style:TextStyle(fontSize:10,color:muted,letterSpacing:1))])),
    ]),
  );

  Widget mobileContent() => ListView(padding:const EdgeInsets.fromLTRB(20,8,20,22),children:[
    hero(),const SizedBox(height:24),sectionTitle('Моя музыка','${tracks.length} треков'),
    const SizedBox(height:12),trackList(),const SizedBox(height:26),spotifyCard(),
  ]);

  Widget wideContent() => Padding(
    padding:const EdgeInsets.fromLTRB(24,8,24,22),
    child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Expanded(flex:6,child:ListView(children:[hero(),const SizedBox(height:24),spotifyCard()])),
      const SizedBox(width:22),
      Expanded(flex:5,child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        sectionTitle('Моя музыка','${tracks.length} треков'),const SizedBox(height:12),Expanded(child:trackList()),
      ])),
    ]),
  );

  Widget hero() => Container(
    padding:const EdgeInsets.all(22),
    decoration:BoxDecoration(
      borderRadius:BorderRadius.circular(26),
      gradient:const LinearGradient(colors:[Color(0xFF29203D),Color(0xFF17131F),panel],begin:Alignment.topLeft,end:Alignment.bottomRight),
      border:Border.all(color:Colors.white.withValues(alpha:.07))),
    child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Container(padding:const EdgeInsets.symmetric(horizontal:10,vertical:6),
        decoration:BoxDecoration(color:violet.withValues(alpha:.16),borderRadius:BorderRadius.circular(20)),
        child:const Text('ТВОЯ МУЗЫКА. ТВОИ ПРАВИЛА.',style:TextStyle(color:Color(0xFFD1C3FF),fontSize:10,fontWeight:FontWeight.w700,letterSpacing:1))),
      const SizedBox(height:18),
      const Text('Слушай то,\nчто любишь.',style:TextStyle(fontSize:34,height:1.08,fontWeight:FontWeight.w800,letterSpacing:-1.1)),
      const SizedBox(height:10),
      const Text('Добавляй свои аудиофайлы и собирай личную музыкальную библиотеку.',style:TextStyle(color:muted,height:1.5,fontSize:13)),
      const SizedBox(height:22),
      SizedBox(width:double.infinity,child:FilledButton.icon(
        onPressed:busy?null:pickFiles,
        icon:busy?const SizedBox(width:17,height:17,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.add_rounded),
        label:Text(busy?'Открываю файлы…':'Добавить музыку'),
        style:FilledButton.styleFrom(backgroundColor:violet,foregroundColor:Colors.white,padding:const EdgeInsets.symmetric(vertical:15),
          shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(14))))),
    ]),
  );

  Widget sectionTitle(String title,String count) => Row(children:[
    Text(title,style:const TextStyle(fontSize:19,fontWeight:FontWeight.w700)),
    const Spacer(),Text(count,style:const TextStyle(color:muted,fontSize:12)),
  ]);

  Widget trackList() {
    if (tracks.isEmpty) {
      return Container(
      padding:const EdgeInsets.symmetric(vertical:28,horizontal:18),
      decoration:BoxDecoration(color:panel,borderRadius:BorderRadius.circular(20),border:Border.all(color:Colors.white.withValues(alpha:.05))),
      child:const Column(children:[
        Icon(Icons.library_music_outlined,size:34,color:muted),SizedBox(height:10),
        Text('Здесь пока пусто',style:TextStyle(fontWeight:FontWeight.w600)),SizedBox(height:5),
        Text('Добавленные аудиофайлы появятся здесь',textAlign:TextAlign.center,style:TextStyle(color:muted,fontSize:12)),
      ]),
      );
    }
    return ListView.separated(
      shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),itemCount:tracks.length,
      separatorBuilder:(_,__)=>const SizedBox(height:7),
      itemBuilder:(context,index){
        final file=tracks[index]; final selected=index==current;
        return Material(color:selected?raised:panel,borderRadius:BorderRadius.circular(15),
          child:InkWell(borderRadius:BorderRadius.circular(15),onTap:()=>loadTrack(index),
            child:Padding(padding:const EdgeInsets.all(11),child:Row(children:[
              Container(width:42,height:42,decoration:BoxDecoration(color:selected?violet.withValues(alpha:.2):const Color(0xFF2B2635),borderRadius:BorderRadius.circular(12)),
                child:Icon(selected?Icons.equalizer_rounded:Icons.music_note_rounded,color:selected?violet:muted)),
              const SizedBox(width:12),
              Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                Text(file.name,maxLines:1,overflow:TextOverflow.ellipsis,style:TextStyle(fontSize:13,fontWeight:FontWeight.w600,color:selected?const Color(0xFFD5C8FF):Colors.white)),
                const SizedBox(height:4),Text('${(file.size/(1024*1024)).toStringAsFixed(1)} МБ',style:const TextStyle(color:muted,fontSize:11)),
              ])),
              Icon(selected?Icons.volume_up_rounded:Icons.play_arrow_rounded,color:selected?violet:muted,size:19),
            ]))),
        );
      },
    );
  }

  Widget spotifyCard() => Container(
    padding:const EdgeInsets.all(18),
    decoration:BoxDecoration(color:panel,borderRadius:BorderRadius.circular(21),border:Border.all(color:Colors.white.withValues(alpha:.05))),
    child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      const Row(children:[Icon(Icons.link_rounded,color:violet),SizedBox(width:9),
        Text('Импорт плейлиста',style:TextStyle(fontSize:15,fontWeight:FontWeight.w700))]),
      const SizedBox(height:8),
      const Text('Вставь ссылку на Spotify-плейлист. Сейчас работает проверка ссылки; получение списка треков требует подключения Spotify API.',
        style:TextStyle(color:muted,fontSize:12,height:1.45)),
      const SizedBox(height:13),
      TextField(controller:spotify,keyboardType:TextInputType.url,style:const TextStyle(fontSize:13),
        decoration:InputDecoration(hintText:'open.spotify.com/playlist/…',hintStyle:const TextStyle(color:muted,fontSize:12),
          filled:true,fillColor:bg,prefixIcon:const Icon(Icons.link,size:19,color:muted),contentPadding:const EdgeInsets.symmetric(vertical:13),
          border:OutlineInputBorder(borderRadius:BorderRadius.circular(13),borderSide:BorderSide.none))),
      const SizedBox(height:10),
      SizedBox(width:double.infinity,child:OutlinedButton(onPressed:checkSpotify,
        style:OutlinedButton.styleFrom(foregroundColor:const Color(0xFFD5C8FF),side:const BorderSide(color:Color(0xFF554477)),
          padding:const EdgeInsets.symmetric(vertical:13),shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(13))),
        child:const Text('Проверить ссылку'))),
    ]),
  );

  Widget playerBar() => Container(
    padding:const EdgeInsets.fromLTRB(18,10,18,10),
    decoration:BoxDecoration(color:const Color(0xFF15121C),border:Border(top:BorderSide(color:Colors.white.withValues(alpha:.07)))),
    child:Column(mainAxisSize:MainAxisSize.min,children:[
      StreamBuilder<Duration>(stream:player.positionStream,builder:(context,snapshot){
        final pos=snapshot.data??Duration.zero;final dur=player.duration??Duration.zero;final max=dur.inMilliseconds.toDouble();
        final value=max<=0?0.0:pos.inMilliseconds.clamp(0,dur.inMilliseconds).toDouble();
        return Column(children:[
          SliderTheme(data:SliderTheme.of(context).copyWith(trackHeight:3,thumbShape:const RoundSliderThumbShape(enabledThumbRadius:5),overlayShape:SliderComponentShape.noOverlay),
            child:Slider(value:value,max:max<=0?1:max,activeColor:violet,inactiveColor:const Color(0xFF393342),
              onChanged:max<=0?null:(v)=>player.seek(Duration(milliseconds:v.round())))),
          Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
            Text(time(pos),style:const TextStyle(color:muted,fontSize:10)),Text(time(dur),style:const TextStyle(color:muted,fontSize:10)),
          ]),
        ]);
      }),
      const SizedBox(height:3),
      Row(children:[
        Container(width:40,height:40,decoration:BoxDecoration(color:raised,borderRadius:BorderRadius.circular(11)),child:const Icon(Icons.music_note_rounded,color:violet)),
        const SizedBox(width:10),
        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(active?.name??'Ничего не играет',maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:12,fontWeight:FontWeight.w700)),
          const SizedBox(height:3),Text(status,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(color:muted,fontSize:10)),
        ])),
        IconButton(tooltip:'Перемешать',onPressed:tracks.isEmpty?null:()=>setState(()=>shuffle=!shuffle),color:shuffle?violet:muted,icon:const Icon(Icons.shuffle_rounded,size:19)),
        IconButton(tooltip:'Предыдущий',onPressed:current<0?null:previous,icon:const Icon(Icons.skip_previous_rounded,size:25)),
        StreamBuilder<PlayerState>(stream:player.playerStateStream,builder:(context,snapshot){
          final playing=snapshot.data?.playing??false;
          return IconButton.filled(tooltip:playing?'Пауза':'Играть',onPressed:active==null?null:()=>playing?player.pause():player.play(),
            style:IconButton.styleFrom(backgroundColor:violet,foregroundColor:Colors.white,minimumSize:const Size(42,42)),
            icon:Icon(playing?Icons.pause_rounded:Icons.play_arrow_rounded));
        }),
        IconButton(tooltip:'Следующий',onPressed:current<0?null:next,icon:const Icon(Icons.skip_next_rounded,size:25)),
        IconButton(tooltip:'Повтор',onPressed:tracks.isEmpty?null:toggleRepeat,color:repeat==LoopMode.off?muted:violet,
          icon:Icon(repeat==LoopMode.one?Icons.repeat_one_rounded:Icons.repeat_rounded,size:19)),
      ]),
    ]),
  );
}
