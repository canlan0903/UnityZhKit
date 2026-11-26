using System;
using System.IO;
using BepInEx;
using BepInEx.Configuration;
using BepInEx.Logging;
using BepInEx.Unity.IL2CPP;
using Il2CppInterop.Runtime.Injection;
using TMPro;
using UnityEngine;
using UnityEngine.TextCore.LowLevel;

namespace ZhFontFix
{
    [BepInPlugin("local.zhfontfix", "ZH Font Fix", "1.3.0")]
    public class Plugin : BasePlugin
    {
        internal static ManualLogSource L;
        internal static ConfigEntry<string> CfgFont;
        internal static ConfigEntry<int> CfgFace;
        internal static ConfigEntry<int> CfgPoint;
        internal static ConfigEntry<int> CfgAtlas;
        internal static ConfigEntry<int> CfgPadding;
        internal static ConfigEntry<float> CfgInterval;

        public override void Load()
        {
            L = Log;
            CfgFont = Config.Bind("Font", "FontPath", @"C:\Windows\Fonts\msyh.ttc",
                "系统字体文件路径（TTF/TTC/OTF）。用支持目标语言字形的字体，例如简体中文用 msyh.ttc / simhei.ttf。");
            CfgFace = Config.Bind("Font", "FaceIndex", 0, "TTC 集合里的字体序号（单文件字体保持 0）。");
            CfgPoint = Config.Bind("Font", "SamplingPointSize", 64, "采样字号，越大越清晰也越占显存。");
            CfgAtlas = Config.Bind("Font", "AtlasSize", 2048, "图集边长（像素）。字形多时用 2048 或 4096。");
            CfgPadding = Config.Bind("Font", "AtlasPadding", 6, "字形间距像素。");
            CfgInterval = Config.Bind("Behaviour", "ScanInterval", 1.5f, "扫描替换文本组件的间隔（秒）。");

            ClassInjector.RegisterTypeInIl2Cpp<FontFixer>();
            var go = new GameObject("ZhFontFixer");
            UnityEngine.Object.DontDestroyOnLoad(go);
            go.hideFlags = HideFlags.HideAndDontSave;
            go.AddComponent<FontFixer>();
            Log.LogInfo("ZhFontFix loaded, font = " + CfgFont.Value);
        }
    }

    public class FontFixer : MonoBehaviour
    {
        private TMP_FontAsset _font;
        private float _next;
        private int _fail;

        public FontFixer(IntPtr ptr) : base(ptr) { }

        public FontFixer() : base(ClassInjector.DerivedConstructorPointer<FontFixer>())
        {
            ClassInjector.DerivedConstructorBody(this);
        }

        private TMP_FontAsset MakeFont()
        {
            string path = Plugin.CfgFont.Value;
            if (!File.Exists(path))
            {
                Plugin.L.LogError("字体文件不存在: " + path);
                return null;
            }
            try
            {
                TMP_FontAsset f = TMP_FontAsset.CreateFontAsset(
                    path,
                    Plugin.CfgFace.Value,
                    Plugin.CfgPoint.Value,
                    Plugin.CfgPadding.Value,
                    GlyphRenderMode.SDFAA,
                    Plugin.CfgAtlas.Value,
                    Plugin.CfgAtlas.Value,
                    AtlasPopulationMode.Dynamic,
                    true);
                if (f != null) Plugin.L.LogInfo("TMP 动态字体已创建: " + path);
                return f;
            }
            catch (Exception e)
            {
                Plugin.L.LogError("创建字体失败 " + path + ": " + e.GetType().Name + " " + e.Message);
                return null;
            }
        }

        private void Update()
        {
            if (Time.unscaledTime < _next) return;
            _next = Time.unscaledTime + Plugin.CfgInterval.Value;
            try
            {
                if (_font == null)
                {
                    if (_fail > 2) { _next = Time.unscaledTime + 30f; return; }
                    _font = MakeFont();
                    if (_font == null) { _fail++; return; }
                }

                int n = 0;
                var uis = Resources.FindObjectsOfTypeAll<TextMeshProUGUI>();
                foreach (var t in uis)
                {
                    if (t == null) continue;
                    if (t.font != _font) { t.font = _font; t.havePropertiesChanged = true; n++; }
                }
                var m3 = Resources.FindObjectsOfTypeAll<TextMeshPro>();
                foreach (var t in m3)
                {
                    if (t == null) continue;
                    if (t.font != _font) { t.font = _font; t.havePropertiesChanged = true; n++; }
                }
                if (n > 0) Plugin.L.LogInfo("已替换 " + n + " 个文本组件的字体");
            }
            catch (Exception e)
            {
                Plugin.L.LogError(e.ToString());
                _next = Time.unscaledTime + 10f;
            }
        }
    }
}
