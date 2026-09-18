/* ============================================================
   经历时间轴：教育经历（覆盖之前内容，分条列举 + 适配图标）
   独立文件，页面加载后强制渲染，避免旧缓存数据覆盖
   ============================================================ */
(function(){
  var TIMELINE = [
    {ico:"🧸", role:"幼儿园", co:"天津大学附属幼儿园",               time:"2010年 - 2014年", desc:"就读于天津大学附属幼儿园。"},
    {ico:"🎒", role:"小学",   co:"天津大学附属小学",                 time:"2014年 - 2020年", desc:"就读于天津大学附属小学。"},
    {ico:"📚", role:"初中",   co:"天津市南开翔宇学校",               time:"2020年 - 2023年", desc:"就读于天津市南开翔宇学校。"},
    {ico:"🏫", role:"高中",   co:"天津市南开中学",                   time:"2023年 - 2026年", desc:"就读于天津市南开中学。"},
    {ico:"🎓", role:"大学",   co:"天津大学香港理工大学深圳未来技术学院", time:"2026年 - 2030年", desc:"就读于天津大学香港理工大学深圳未来技术学院。"}
  ];

  function esc(s){return String(s==null?"":s).replace(/[&<>"']/g,function(m){return {"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[m];});}

  function render(){
    var el = document.getElementById("timeline");
    if(!el) return;
    el.innerHTML = TIMELINE.map(function(t){
      return '<div class="t-item">'
        + '<div class="role"><span class="stage-icon" aria-hidden="true">' + esc(t.ico) + '</span><span>' + esc(t.role) + '</span></div>'
        + '<div class="co">' + esc(t.co) + '</div>'
        + '<div class="time">' + esc(t.time) + '</div>'
        + '<p>' + esc(t.desc) + '</p>'
        + '</div>';
    }).join("");
  }

  if(document.readyState === "loading"){
    document.addEventListener("DOMContentLoaded", render);
  } else {
    render();
  }

  /* 页面内 renderAll()/语言切换会重绘 #timeline，用 MutationObserver 兜底再渲染一次 */
  var box = document.getElementById("timeline");
  if(box && box.parentNode){
    var timer = null;
    new MutationObserver(function(){
      if(timer) return;
      timer = setTimeout(function(){ timer = null; render(); }, 200);
    }).observe(box.parentNode, {childList:true, subtree:true});
  }
})();
