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
  /* On a reply page, tell the stream which post is selected so re-rendered
     threads keep the highlight. */
  var reply = document.body.getAttribute("data-live-reply");
  if (reply) url += "?reply=" + encodeURIComponent(reply);
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

  function makeGroup(key, latest) {
    var box = document.createElement("details");
    box.className = "post_group";
    box.id = "group-" + key;
    /* Matches the server: the newest day arrives open, older ones closed. A
       group that already exists keeps whatever the reader left it at. */
    box.open = latest;
    box.innerHTML = "<summary class=\"post_group_header\">" +
      "<span class=\"post_group_label\"></span>" +
      "<span class=\"post_group_count\"></span></summary>";
    return box;
  }

  /* Threads are filed under a date heading, so placing an arrival means
     knowing which day it belongs to -- and a bump can move a thread from one
     day to another, into a day the page may not have yet. Rather than work
     that out here, the server sends the layout it should end up with and this
     walks it: groups into place, then threads into their group.

     Everything is a move rather than a rebuild, so a <details> the reader
     collapsed stays collapsed. */
  function applyGroups(groups) {
    var anchor = document.getElementById("board_top");
    if (!anchor) return;
    var previous = anchor;
    var wanted = Object.create(null);

    groups.forEach(function (group, index) {
      var id = "group-" + group.key;
      wanted[id] = true;
      var box = document.getElementById(id) || makeGroup(group.key, index === 0);
      /* Relabelled rather than rebuilt: "Today" becomes "Yesterday" at
         midnight without the page being reloaded. */
      box.querySelector(".post_group_label").textContent = group.label;
      box.querySelector(".post_group_count").textContent = group.ids.length;
      if (previous.nextElementSibling !== box) previous.after(box);
      previous = box;

      var mark = box.querySelector(".post_group_header");
      group.ids.forEach(function (postId) {
        var node = document.getElementById("post-" + postId);
        if (!node) return;
        if (mark.nextElementSibling !== node) mark.after(node);
        mark = node;
      });
    });

    /* A day whose last thread was purged, or bumped into another day. */
    Array.prototype.forEach.call(root.querySelectorAll(".post_group"), function (box) {
      if (!wanted[box.id]) box.remove();
    });
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

    if (data.groups) applyGroups(data.groups);
    markArrivals(before);

    if (data.stats) {
      var stats = document.querySelector(".collapsed_board_header");
      if (stats) stats.textContent = data.stats;
    }
  };
})();
