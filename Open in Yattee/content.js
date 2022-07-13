if (document.readyState !== 'complete') {
    window.addEventListener('load', redirect);
} else {
    redirect();
}

function yatteeUrl() {
    return window.location.href.replace(/^https?:\/\//, 'yattee://');
}

function yatteeLink() {
    return '<a href="'+ yatteeUrl() +'" onclick=\'window.location.href="'+ yatteeUrl() +'"\'>Open in Yattee</a>';
}

function redirect() {
    window.location.href = yatteeUrl()
}
