/* Live mode. The only JavaScript this application ships, and it ships only
   when the live_mode cookie is "on" -- see ApplicationController#live_runtime.
   No framework, no build step, no dependencies.

   The server holds the cursor and the set of threads this page is showing, so
   there is nothing to send after the initial request. Everything below is
   applying what arrives. */
(function () {
  "use strict";

  var root = document.getElementById("post-root");
  var scope = document.body.getAttribute("data-live-scope");
  if (!root || scope === null) return;

  var url = scope === "" ? "/feed" : "/feed/" + encodeURIComponent(scope);
  var source = new EventSource(url);

  /* Every post id currently on the page. Used to tell an arrival from a
     re-render: a thread that gains a reply is replaced wholesale, and only
     the posts that were not there before should be animated. */
  function postIds() {
    var seen = Object.create(null);
    var nodes = root.querySelectorAll("details.post[id]");
    for (var i = 0; i < nodes.length; i++) seen[nodes[i].id] = true;
    return seen;
  }

  function parse(html) {
    var holder = document.createElement("div");
    holder.innerHTML = html;
    return holder.firstElementChild;
  }

  /* The board renders newest first. Rather than compute where each arrival
     belongs, the server sends the order it should be in and we walk it --
     which also re-sorts threads that were bumped by a reply. */
  function applyOrder(ids) {
    var previous = document.getElementById("board_top");
    if (!previous) return;
    for (var i = 0; i < ids.length; i++) {
      var node = document.getElementById("post-" + ids[i]);
      if (!node) continue;
      if (previous.nextElementSibling !== node) previous.after(node);
      previous = node;
    }
  }

  function markArrivals(before) {
    var nodes = root.querySelectorAll("details.post[id]");
    for (var i = 0; i < nodes.length; i++) {
      var node = nodes[i];
      if (before[node.id]) continue;
      node.classList.add("post_arriving");
      /* Dropped once played, so a later re-render of the same thread does not
         replay it. */
      node.addEventListener("animationend", function () {
        this.classList.remove("post_arriving");
      }, { once: true });
    }
  }

  source.onmessage = function (event) {
    var data = JSON.parse(event.data);
    if (data.hello) return;
    if (data.reload) { location.reload(); return; }

    var before = postIds();

    (data.remove || []).forEach(function (id) {
      var node = document.getElementById("post-" + id);
      if (node) node.remove();
    });

    (data.replace || []).forEach(function (thread) {
      var node = document.getElementById("post-" + thread.id);
      var fresh = parse(thread.html);
      if (node && fresh) node.replaceWith(fresh);
    });

    (data.insert || []).forEach(function (thread) {
      var fresh = parse(thread.html);
      if (fresh && !document.getElementById(fresh.id)) root.appendChild(fresh);
    });

    if (data.order) applyOrder(data.order);
    markArrivals(before);

    if (data.stats) {
      var stats = document.querySelector(".collapsed_board_header");
      if (stats) stats.textContent = data.stats;
    }
  };
})();
