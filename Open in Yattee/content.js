if (document.readyState !== 'complete') {
    window.addEventListener('load', redirectAndReplaceContentWithLink);
} else {
    redirectAndReplaceContentWithLink();
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

function replaceContentWithLink() {
    document.querySelector('body').innerHTML = '<h1>' + yatteeLink() + '</h1>';
}

function redirectAndReplaceContentWithLink(){
    redirect()
    replaceContentWithLink()
}
