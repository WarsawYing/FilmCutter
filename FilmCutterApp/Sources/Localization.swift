import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, en, zhHans = "zh-Hans", ja, es, fr
    var id: String { rawValue }
    var menuName: String {
        switch self {
        case .system: return "System / 跟随系统"
        case .en: return "English"
        case .zhHans: return "简体中文"
        case .ja: return "日本語"
        case .es: return "Español"
        case .fr: return "Français"
        }
    }
    var locale: Locale { Locale(identifier: resolvedIdentifier) }
    var resolvedIdentifier: String {
        if self != .system { return rawValue }
        return Self.resolvedIdentifier(for: Locale.preferredLanguages.first ?? "en")
    }
    static func resolvedIdentifier(for preferred: String) -> String {
        if preferred.hasPrefix("zh") { return "zh-Hans" }
        if preferred.hasPrefix("ja") { return "ja" }
        if preferred.hasPrefix("es") { return "es" }
        if preferred.hasPrefix("fr") { return "fr" }
        return "en"
    }
}

@MainActor
final class LocalizationStore: ObservableObject {
    @Published var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: "filmcutter.language") }
    }
    init() {
        language = AppLanguage(rawValue: UserDefaults.standard.string(forKey: "filmcutter.language") ?? "system") ?? .system
    }
    func text(_ key: String, _ args: CVarArg...) -> String {
        text(key, arguments: args)
    }
    func text(_ key: String, arguments: [CVarArg]) -> String {
        let table = Self.resolvedTables()[language.resolvedIdentifier] ?? Self.tables["en"]!
        let format = table[key] ?? Self.tables["en"]![key] ?? key
        return String(format: format, locale: language.locale, arguments: arguments)
    }
    func plural(_ key: String, count: Int) -> String {
        text("\(key).\(count == 1 ? "one" : "other")", count)
    }

    static let tables: [String: [String: String]] = [
        "en": [
            "about":"About FilmCutter", "about.description":"Cut scanned film strips into individual frames.\nSupports 8/16-bit TIFF scans.", "source":"Source", "license":"License", "third.party":"Third-Party Notices", "contributors":"Contributors",
            "stage.import":"Import", "stage.adjust":"Preview & Adjust", "stage.export":"Export Confirmation",
            "drop.title":"Drop a scanned film TIFF here", "drop.subtitle":"Drop one TIFF file or a folder for batch processing",
            "select.file":"Select File…", "select.folder":"Select Folder…", "select.input.again":"Choose Different Input",
            "roll.name":"Roll Name", "roll.placeholder":"e.g. Paris2026", "film.format":"Film Format",
            "expected.count":"Expected frames (optional)", "experimental.refine":"Experimental boundary refinement",
            "negative":"Negative (invert)", "positive":"Positive (keep)", "border":"Border: %d px",
            "metadata":"Roll Metadata", "camera":"Camera", "lens":"Lens", "film.stock":"Film Stock",
            "push.pull":"Push/Pull", "aperture":"Aperture", "date":"Date", "today":"Today", "scanner":"Scanner", "notes":"Notes",
            "scan.info":"Scan %d of %d", "file":"File", "size":"Size", "depth":"Depth", "frames":"Frames",
            "found.frames":"Found %d", "found.frames.one":"Found %d frame", "found.frames.other":"Found %d frames", "expected.found":"Expected %d / Found %d", "manual.adjustments":"Manual adjustments",
            "previous":"Previous", "next":"Next", "update.detection":"Update Detection", "update.scope":"Apply to",
            "reorder.frames":"Renumber frames in reading order", "frame.geometry.warning":"Some frames overlap. Check them before export.",
            "scope.current":"Current Scan", "scope.all":"All Scans", "approve":"Continue with %d Frames →",
            "back":"Back", "change":"Change…", "output":"Output", "filename.preview":"Filename Preview",
            "export":"Cut %d Frames →", "processing":"Cutting frames…", "error":"Error", "back.adjust":"Back to Adjustments",
            "try.again":"Try Again", "complete":"Successfully cut %d frames!", "open.output":"Open Output Folder", "process.another":"Process Another",
            "replace.title":"Replace manual adjustments?", "replace.message":"Automatic detection will replace manual edits for the selected scan scope.",
            "cancel":"Cancel", "replace":"Replace", "name.required":"Enter a roll name", "name.preview":"%@ … %@",
            "confirm.reselect.title":"Choose different input?", "confirm.reselect.message":"Manual frame adjustments will be discarded.",
            "format.auto":"Auto", "format.135":"135 Full Frame (24×36)", "format.135_half":"135 Half Frame (18×24)",
            "format.65x24":"65×24", "format.645":"645 / 6×4.5", "format.66":"6×6", "format.67":"6×7",
            "format.68":"6×8", "format.69":"6×9", "format.612":"6×12", "format.617":"6×17",
            "PROGRESS_START":"Starting…", "PROGRESS_PREVIEW_FILE":"Scanning %@", "PROGRESS_PREVIEW_COMPLETE":"Preview ready",
            "PROGRESS_PROCESS_FILE":"Processing %@", "PROGRESS_PROCESS_COMPLETE":"Finishing TIFF files…",
            "ERR_NO_INPUT":"No TIFF input was provided.", "ERR_NO_FRAMES":"No frames were detected. Add a frame manually or update detection.", "ERR_PREVIEW_PARTIAL":"One or more scans could not be previewed.",
            "ERR_OUTPUT_COLLISION":"Output files already exist. Change the roll name or output folder.",
            "ERR_PROCESS":"Processing failed. No partial output was kept.", "ERR_ENGINE":"The embedded processing engine failed.",
            "refine.no_frames":"Refinement skipped: no frames were found.", "refine.geometry_guard":"Refinement reverted to preserve frame geometry.",
            "refine.overlap_guard":"Refinement reverted to prevent overlapping frames.", "refine.no_score_improvement":"The stable detection boundaries were already better."
        ],
        "zh-Hans": [
            "about":"关于 FilmCutter", "about.description":"将胶片扫描稿裁切为独立画格。\n支持 8/16 位 TIFF 扫描稿。", "source":"源代码", "license":"许可证", "third.party":"第三方声明", "contributors":"贡献者",
            "stage.import":"导入", "stage.adjust":"预览与调整", "stage.export":"导出确认",
            "drop.title":"将胶片扫描 TIFF 拖到这里", "drop.subtitle":"拖入一个 TIFF 文件，或拖入文件夹进行批量处理",
            "select.file":"选择文件…", "select.folder":"选择文件夹…", "select.input.again":"重新选择输入",
            "roll.name":"胶卷名称", "roll.placeholder":"例如：上海2026", "film.format":"胶片格式",
            "expected.count":"预期画格数（可选）", "experimental.refine":"实验性边界细化",
            "negative":"负片（反相）", "positive":"正片（保持）", "border":"边框：%d px",
            "metadata":"胶卷资料", "camera":"相机", "lens":"镜头", "film.stock":"胶卷型号",
            "push.pull":"增感/减感", "aperture":"光圈", "date":"日期", "today":"今天", "scanner":"扫描仪", "notes":"备注",
            "scan.info":"扫描稿 %d / %d", "file":"文件", "size":"尺寸", "depth":"位深", "frames":"画格",
            "found.frames":"找到 %d 个画格", "found.frames.one":"找到 %d 个画格", "found.frames.other":"找到 %d 个画格", "expected.found":"预期 %d / 找到 %d", "manual.adjustments":"已手动调整",
            "previous":"上一张", "next":"下一张", "update.detection":"更新检测", "update.scope":"应用范围",
            "reorder.frames":"按画格阅读顺序重新编号", "frame.geometry.warning":"部分画格重叠，请在导出前检查。",
            "scope.current":"当前扫描稿", "scope.all":"全部扫描稿", "approve":"确认 %d 个画格并继续 →",
            "back":"返回", "change":"更改…", "output":"输出位置", "filename.preview":"文件名预览",
            "export":"裁切 %d 个画格 →", "processing":"正在裁切画格…", "error":"错误", "back.adjust":"返回调整",
            "try.again":"重试", "complete":"已成功裁切 %d 个画格！", "open.output":"打开输出文件夹", "process.another":"处理另一卷",
            "replace.title":"替换手动调整？", "replace.message":"自动检测会替换所选范围内的手动画格调整。",
            "cancel":"取消", "replace":"替换", "name.required":"请输入胶卷名称", "name.preview":"%@ … %@",
            "confirm.reselect.title":"重新选择输入？", "confirm.reselect.message":"现有的手动画格调整将被丢弃。",
            "format.auto":"自动", "format.135":"135 全格（24×36）", "format.135_half":"135 半格（18×24）",
            "format.65x24":"65×24", "format.645":"645 / 6×4.5", "format.66":"6×6", "format.67":"6×7",
            "format.68":"6×8", "format.69":"6×9", "format.612":"6×12", "format.617":"6×17",
            "PROGRESS_START":"正在准备…", "PROGRESS_PREVIEW_FILE":"正在检测 %@", "PROGRESS_PREVIEW_COMPLETE":"预览已生成",
            "PROGRESS_PROCESS_FILE":"正在处理 %@", "PROGRESS_PROCESS_COMPLETE":"正在完成 TIFF 文件…",
            "ERR_NO_INPUT":"没有提供 TIFF 扫描稿。", "ERR_NO_FRAMES":"未检测到画格，请手动添加或更新检测。", "ERR_PREVIEW_PARTIAL":"部分扫描稿无法生成预览。",
            "ERR_OUTPUT_COLLISION":"输出文件已存在，请更换胶卷名称或输出位置。", "ERR_PROCESS":"处理失败，未保留不完整文件。",
            "ERR_ENGINE":"内置处理引擎运行失败。", "refine.no_frames":"未找到画格，已跳过边界细化。",
            "refine.geometry_guard":"为保持画格比例，已恢复原检测边界。", "refine.overlap_guard":"为防止画格重叠，已恢复原检测边界。",
            "refine.no_score_improvement":"原检测边界已经更好。"
        ],
        "ja": [
            "about":"FilmCutterについて", "about.description":"スキャンしたフィルムを1コマずつTIFFに切り出します。", "source":"ソース", "license":"ライセンス", "third.party":"第三者ライセンス", "contributors":"コントリビューター",
            "stage.import":"読み込み", "stage.adjust":"プレビューと調整", "stage.export":"書き出し確認",
            "drop.title":"スキャンしたフィルムTIFFをドロップ", "drop.subtitle":"TIFFファイルまたは一括処理するフォルダをドロップ",
            "select.file":"ファイルを選択…", "select.folder":"フォルダを選択…", "select.input.again":"入力を選び直す",
            "roll.name":"ロール名", "roll.placeholder":"例：Tokyo2026", "film.format":"フィルムフォーマット", "expected.count":"想定コマ数（任意）",
            "experimental.refine":"実験的な境界補正", "frames":"コマ", "found.frames":"%dコマ検出", "found.frames.one":"%dコマ検出", "found.frames.other":"%dコマ検出", "expected.found":"想定 %d / 検出 %d", "manual.adjustments":"手動調整あり",
            "negative":"ネガ（反転）", "positive":"ポジ（維持）", "border":"余白：%d px", "metadata":"ロール情報",
            "camera":"カメラ", "lens":"レンズ", "film.stock":"フィルム銘柄", "push.pull":"増感／減感", "aperture":"絞り", "date":"日付", "today":"今日", "scanner":"スキャナー", "notes":"メモ",
            "scan.info":"スキャン %d / %d", "file":"ファイル", "size":"サイズ", "depth":"ビット深度",
            "previous":"前へ", "next":"次へ", "update.detection":"再検出", "update.scope":"適用範囲", "scope.current":"現在のスキャン", "scope.all":"すべてのスキャン",
            "reorder.frames":"読み順にコマ番号を付け直す", "frame.geometry.warning":"重なっているコマがあります。書き出し前に確認してください。",
            "approve":"%dコマで続ける →", "back":"戻る", "change":"変更…", "output":"出力先", "filename.preview":"ファイル名プレビュー",
            "export":"%dコマを書き出す →", "processing":"コマを書き出しています…", "error":"エラー", "back.adjust":"調整に戻る",
            "try.again":"もう一度試す", "complete":"%dコマを書き出しました！", "open.output":"出力フォルダを開く", "process.another":"別のロールを処理",
            "replace.title":"手動調整を置き換えますか？", "replace.message":"自動検出により、選択範囲の手動調整が置き換えられます。", "cancel":"キャンセル", "replace":"置き換える",
            "name.required":"ロール名を入力してください", "name.preview":"%@ … %@", "confirm.reselect.title":"入力を選び直しますか？", "confirm.reselect.message":"現在の手動調整は破棄されます。",
            "format.auto":"自動", "format.135":"135 フルサイズ（24×36）", "format.135_half":"135 ハーフ（18×24）",
            "format.65x24":"65×24", "format.645":"645 / 6×4.5", "format.66":"6×6", "format.67":"6×7", "format.68":"6×8", "format.69":"6×9", "format.612":"6×12", "format.617":"6×17",
            "PROGRESS_START":"準備中…", "PROGRESS_PREVIEW_FILE":"%@を検出中", "PROGRESS_PREVIEW_COMPLETE":"プレビューの準備完了", "PROGRESS_PROCESS_FILE":"%@を処理中", "PROGRESS_PROCESS_COMPLETE":"TIFFを仕上げています…",
            "ERR_NO_INPUT":"TIFFスキャンが選択されていません。", "ERR_NO_FRAMES":"コマを検出できませんでした。手動で追加するか再検出してください。", "ERR_PREVIEW_PARTIAL":"一部のスキャンをプレビューできませんでした。", "ERR_OUTPUT_COLLISION":"同名の出力ファイルがあります。ロール名または出力先を変更してください。", "ERR_PROCESS":"処理に失敗しました。不完全な出力は保存されていません。", "ERR_ENGINE":"内蔵処理エンジンでエラーが発生しました。",
            "refine.no_frames":"コマがないため境界補正を省略しました。", "refine.geometry_guard":"コマ形状を保つため元の検出境界に戻しました。", "refine.overlap_guard":"重なりを防ぐため元の検出境界に戻しました。", "refine.no_score_improvement":"元の検出境界の方が適切です。"
        ],
        "es": [
            "about":"Acerca de FilmCutter", "about.description":"Recorta película escaneada en fotogramas TIFF individuales.", "source":"Código fuente", "license":"Licencia", "third.party":"Avisos de terceros", "contributors":"Colaboradores",
            "stage.import":"Importar", "stage.adjust":"Vista previa y ajuste", "stage.export":"Confirmar exportación",
            "drop.title":"Suelta aquí un TIFF de película escaneada", "drop.subtitle":"Suelta un TIFF o una carpeta para procesarla por lotes", "select.file":"Elegir archivo…", "select.folder":"Elegir carpeta…",
            "select.input.again":"Elegir otra entrada", "roll.name":"Nombre del carrete", "roll.placeholder":"p. ej., Madrid2026", "film.format":"Formato de película",
            "expected.count":"Fotogramas esperados (opcional)", "experimental.refine":"Ajuste experimental de bordes",
            "negative":"Negativo (invertir)", "positive":"Positivo (conservar)", "border":"Borde: %d px", "metadata":"Datos del carrete",
            "camera":"Cámara", "lens":"Objetivo", "film.stock":"Película", "push.pull":"Forzado", "aperture":"Apertura", "date":"Fecha", "today":"Hoy", "scanner":"Escáner", "notes":"Notas",
            "scan.info":"Escaneo %d de %d", "file":"Archivo", "size":"Tamaño", "depth":"Profundidad", "frames":"Fotogramas", "found.frames":"%d fotogramas encontrados", "found.frames.one":"%d fotograma encontrado", "found.frames.other":"%d fotogramas encontrados", "expected.found":"Esperados %d / Encontrados %d", "manual.adjustments":"Ajustes manuales",
            "previous":"Anterior", "next":"Siguiente", "update.detection":"Actualizar detección", "update.scope":"Aplicar a", "scope.current":"Escaneo actual", "scope.all":"Todos",
            "reorder.frames":"Renumerar fotogramas en orden de lectura", "frame.geometry.warning":"Hay fotogramas solapados. Revísalos antes de exportar.",
            "approve":"Continuar con %d fotogramas →", "back":"Atrás", "change":"Cambiar…", "output":"Destino", "filename.preview":"Vista previa del nombre",
            "export":"Recortar %d fotogramas →", "processing":"Recortando fotogramas…", "error":"Error", "back.adjust":"Volver a los ajustes",
            "try.again":"Intentar de nuevo", "complete":"¡%d fotogramas recortados!", "open.output":"Abrir carpeta de salida", "process.another":"Procesar otro carrete",
            "replace.title":"¿Sustituir los ajustes manuales?", "replace.message":"La detección automática sustituirá los ajustes manuales del ámbito elegido.", "cancel":"Cancelar", "replace":"Sustituir", "name.required":"Introduce un nombre para el carrete", "name.preview":"%@ … %@", "confirm.reselect.title":"¿Elegir otra entrada?", "confirm.reselect.message":"Se descartarán los ajustes manuales actuales.",
            "format.auto":"Automático", "format.135":"135 completo (24×36)", "format.135_half":"135 medio formato (18×24)",
            "format.65x24":"65×24", "format.645":"645 / 6×4.5", "format.66":"6×6", "format.67":"6×7", "format.68":"6×8", "format.69":"6×9", "format.612":"6×12", "format.617":"6×17",
            "PROGRESS_START":"Preparando…", "PROGRESS_PREVIEW_FILE":"Detectando %@", "PROGRESS_PREVIEW_COMPLETE":"Vista previa lista", "PROGRESS_PROCESS_FILE":"Procesando %@", "PROGRESS_PROCESS_COMPLETE":"Terminando los TIFF…", "ERR_NO_INPUT":"No se ha indicado ningún TIFF.", "ERR_NO_FRAMES":"No se detectaron fotogramas. Añade uno manualmente o actualiza la detección.", "ERR_PREVIEW_PARTIAL":"No se pudo previsualizar uno o más escaneos.", "ERR_OUTPUT_COLLISION":"Ya existen archivos de salida. Cambia el nombre del carrete o la carpeta.", "ERR_PROCESS":"El proceso falló. No se conservó ninguna salida parcial.", "ERR_ENGINE":"Falló el motor de procesamiento integrado.",
            "refine.no_frames":"No se ajustaron los bordes porque no se encontraron fotogramas.", "refine.geometry_guard":"Se restauraron los bordes originales para conservar la geometría.", "refine.overlap_guard":"Se restauraron los bordes originales para evitar solapamientos.", "refine.no_score_improvement":"Los bordes originales ya eran mejores."
        ],
        "fr": [
            "about":"À propos de FilmCutter", "about.description":"Découpe les films numérisés en vues TIFF individuelles.", "source":"Code source", "license":"Licence", "third.party":"Mentions tierces", "contributors":"Contributeurs",
            "stage.import":"Importer", "stage.adjust":"Aperçu et réglage", "stage.export":"Confirmation d’export",
            "drop.title":"Déposez ici un TIFF de film numérisé", "drop.subtitle":"Déposez un TIFF ou un dossier pour le traitement par lot", "select.file":"Choisir un fichier…", "select.folder":"Choisir un dossier…",
            "select.input.again":"Changer d’entrée", "roll.name":"Nom de la pellicule", "roll.placeholder":"ex. Paris2026", "film.format":"Format de film",
            "expected.count":"Vues attendues (facultatif)", "experimental.refine":"Affinage expérimental des bords",
            "negative":"Négatif (inverser)", "positive":"Positif (conserver)", "border":"Bordure : %d px", "metadata":"Informations de la pellicule",
            "camera":"Appareil", "lens":"Objectif", "film.stock":"Pellicule", "push.pull":"Push/Pull", "aperture":"Ouverture", "date":"Date", "today":"Aujourd’hui", "scanner":"Scanner", "notes":"Notes",
            "scan.info":"Scan %d sur %d", "file":"Fichier", "size":"Dimensions", "depth":"Profondeur", "frames":"Vues", "found.frames":"%d vues détectées", "found.frames.one":"%d vue détectée", "found.frames.other":"%d vues détectées", "expected.found":"%d attendues / %d détectées", "manual.adjustments":"Réglages manuels",
            "previous":"Précédent", "next":"Suivant", "update.detection":"Relancer la détection", "update.scope":"Appliquer à", "scope.current":"Scan actuel", "scope.all":"Tous les scans",
            "reorder.frames":"Renuméroter les vues dans l’ordre de lecture", "frame.geometry.warning":"Certaines vues se chevauchent. Vérifiez-les avant l’export.",
            "approve":"Continuer avec %d vues →", "back":"Retour", "change":"Modifier…", "output":"Destination", "filename.preview":"Aperçu du nom",
            "export":"Découper %d vues →", "processing":"Découpe en cours…", "error":"Erreur", "back.adjust":"Retour aux réglages",
            "try.again":"Réessayer", "complete":"%d vues découpées !", "open.output":"Ouvrir le dossier de sortie", "process.another":"Traiter une autre pellicule",
            "replace.title":"Remplacer les réglages manuels ?", "replace.message":"La détection automatique remplacera les réglages manuels pour la portée choisie.", "cancel":"Annuler", "replace":"Remplacer", "name.required":"Saisissez un nom de pellicule", "name.preview":"%@ … %@", "confirm.reselect.title":"Changer d’entrée ?", "confirm.reselect.message":"Les réglages manuels actuels seront supprimés.",
            "format.auto":"Automatique", "format.135":"135 plein format (24×36)", "format.135_half":"135 demi-format (18×24)",
            "format.65x24":"65×24", "format.645":"645 / 6×4.5", "format.66":"6×6", "format.67":"6×7", "format.68":"6×8", "format.69":"6×9", "format.612":"6×12", "format.617":"6×17",
            "PROGRESS_START":"Préparation…", "PROGRESS_PREVIEW_FILE":"Détection de %@", "PROGRESS_PREVIEW_COMPLETE":"Aperçu prêt", "PROGRESS_PROCESS_FILE":"Traitement de %@", "PROGRESS_PROCESS_COMPLETE":"Finalisation des TIFF…", "ERR_NO_INPUT":"Aucun TIFF n’a été fourni.", "ERR_NO_FRAMES":"Aucune vue détectée. Ajoutez-en une manuellement ou relancez la détection.", "ERR_PREVIEW_PARTIAL":"Un ou plusieurs scans n’ont pas pu être prévisualisés.", "ERR_OUTPUT_COLLISION":"Des fichiers de sortie existent déjà. Modifiez le nom ou le dossier.", "ERR_PROCESS":"Le traitement a échoué. Aucun fichier partiel n’a été conservé.", "ERR_ENGINE":"Le moteur de traitement intégré a échoué.",
            "refine.no_frames":"Affinage ignoré : aucune vue détectée.", "refine.geometry_guard":"Retour aux bords d’origine pour préserver la géométrie.", "refine.overlap_guard":"Retour aux bords d’origine pour éviter le chevauchement.", "refine.no_score_improvement":"Les bords d’origine étaient déjà meilleurs."
        ]
    ]

    static func resolvedTables() -> [String: [String: String]] {
        let english = tables["en"] ?? [:]
        return tables.mapValues { $0.fillingMissing(from: english) }
    }
}

extension Dictionary where Key == String, Value == String {
    func fillingMissing(from fallback: [String: String]) -> [String: String] {
        fallback.merging(self) { _, localized in localized }
    }
}
