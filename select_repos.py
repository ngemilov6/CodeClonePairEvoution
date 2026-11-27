import json, os, time
import requests

# ---------- configuration ----------
TOKEN = os.environ["GITHUB_TOKEN"]
TARGET = 100000
MIN_JAVA_SHARE = 0.95
MIN_CONTRIBUTORS = 3  # more than two
MIN_STARS = 20
PUSHED_AFTER = "2025-01-01"
PRE_WINDOW = ("2018-01-01T00:00:00Z", "2020-01-01T00:00:00Z")
POST_WINDOW = ("2020-01-01T00:00:00Z", "2022-01-01T00:00:00Z")
SAMPLE = 50  # commits sampled per window
PAGE_SIZE = 30  # light query, so this can be larger
PER_SLICE_CAP = 10000
OUT = "selected.jsonl"
# -----------------------------------

URL = "https://api.github.com/graphql"
session = requests.Session()
session.headers["Authorization"] = f"Bearer {TOKEN}"

SEARCH_Q = """
query($q: String!, $cursor: String, $n: Int!) {
  search(query: $q, type: REPOSITORY, first: $n, after: $cursor) {
    pageInfo { hasNextPage endCursor }
    nodes {
      ... on Repository {
        nameWithOwner
        stargazerCount
        pushedAt
        languages(first: 10, orderBy: {field: SIZE, direction: DESC}) {
          totalSize
          edges { size node { name } }
        }
      }
    }
  }
}
"""

HISTORY_Q = """
query($owner: String!, $name: String!, $sample: Int!,
      $preSince: GitTimestamp, $preUntil: GitTimestamp,
      $postSince: GitTimestamp, $postUntil: GitTimestamp) {
  repository(owner: $owner, name: $name) {
    defaultBranchRef {
      name
      target {
        ... on Commit {
          oid
          pre:  history(first: $sample, since: $preSince,  until: $preUntil)  { nodes { author { user { login } email } } }
          post: history(first: $sample, since: $postSince, until: $postUntil) { nodes { author { user { login } email } } }
        }
      }
    }
  }
}
"""


def gql(query, variables, retries=4):
    """Returns the 'data' dict, or None if the request keeps failing."""
    for attempt in range(retries):
        try:
            r = session.post(
                URL, json={"query": query, "variables": variables}, timeout=90
            )
        except requests.RequestException as e:
            print(f"  [attempt {attempt+1}] network error: {e}")
            time.sleep(2**attempt * 3)
            continue
        if r.status_code == 401:
            raise SystemExit("401 Unauthorized: check GITHUB_TOKEN")
        if r.status_code in (403, 429):
            wait = int(r.headers.get("Retry-After", 2**attempt * 15))
            print(
                f"  [attempt {attempt+1}] {r.status_code} rate limited, sleeping {wait}s"
            )
            time.sleep(wait)
            continue
        if r.status_code >= 500:
            print(f"  [attempt {attempt+1}] {r.status_code} server error")
            time.sleep(2**attempt * 3)
            continue
        body = r.json()
        if body.get("data") is None:
            print("  GraphQL errors:", json.dumps(body.get("errors"))[:500])
            return None
        return body["data"]  # partial errors (e.g. one null repo) are tolerated
    return None


def java_share(repo):
    langs = repo["languages"]
    if not langs["totalSize"]:
        return 0.0
    java = sum(e["size"] for e in langs["edges"] if e["node"]["name"] == "Java")
    return java / langs["totalSize"]


def distinct_authors(history):
    ids = set()
    for c in history["nodes"]:
        a = c.get("author") or {}
        ident = (a.get("user") or {}).get("login") or (a.get("email") or "")
        ident = ident.lower()
        if not ident or "[bot]" in ident or "bot@" in ident:
            continue
        ids.add(ident)
    return ids


def check_history(repo, share):
    owner, name = repo["nameWithOwner"].split("/", 1)
    data = gql(
        HISTORY_Q,
        {
            "owner": owner,
            "name": name,
            "sample": SAMPLE,
            "preSince": PRE_WINDOW[0],
            "preUntil": PRE_WINDOW[1],
            "postSince": POST_WINDOW[0],
            "postUntil": POST_WINDOW[1],
        },
    )
    if not data or not data.get("repository"):
        return None
    ref = data["repository"].get("defaultBranchRef")
    if not ref or not ref.get("target"):
        return None
    pre = distinct_authors(ref["target"]["pre"])
    post = distinct_authors(ref["target"]["post"])
    if len(pre) < MIN_CONTRIBUTORS or len(post) < MIN_CONTRIBUTORS:
        return None
    return {
        "repo": repo["nameWithOwner"],
        "branch": ref["name"],
        "head_oid": ref["target"]["oid"],
        "java_share": round(share, 3),
        "stars": repo["stargazerCount"],
        "pushed_at": repo["pushedAt"],
        "contributors_pre_sample": len(pre),
        "contributors_post_sample": len(post),
    }


def main():
    done = set()
    if os.path.exists(OUT):
        done = {json.loads(l)["repo"] for l in open(OUT)}
    total = len(done)
    print(f"resuming with {total} already selected")

    with open(OUT, "a") as out:
        for year in range(2019, 2020):
            if total >= TARGET:
                break
            q = (
                f"language:java stars:>={MIN_STARS} fork:false archived:false "
                f"created:{year}-01-01..{year}-12-31 pushed:>={PUSHED_AFTER} sort:stars-desc"
            )
            cursor, accepted, checked = None, 0, 0
            while total < TARGET and accepted < PER_SLICE_CAP:
                data = gql(SEARCH_Q, {"q": q, "cursor": cursor, "n": PAGE_SIZE})
                if not data:
                    print(f"  skipping rest of {year} after repeated failures")
                    break
                page = data["search"]
                for repo in page["nodes"]:
                    if not repo or repo["nameWithOwner"] in done:
                        continue
                    share = java_share(repo)
                    if share < MIN_JAVA_SHARE:
                        continue
                    checked += 1
                    rec = check_history(repo, share)
                    if rec:
                        out.write(json.dumps(rec) + "\n")
                        out.flush()
                        done.add(rec["repo"])
                        accepted += 1
                        total += 1
                        print(f"  + {rec['repo']}  ({total}/{TARGET})")
                        if total >= TARGET or accepted >= PER_SLICE_CAP:
                            break
                    time.sleep(0.5)
                print(
                    f"{year}: accepted {accepted}, history-checked {checked}, total {total}"
                )
                if not page["pageInfo"]["hasNextPage"]:
                    break
                cursor = page["pageInfo"]["endCursor"]
                time.sleep(2)

    print(f"done: {total} repos in {OUT}")
    if total < TARGET:
        print(
            "Short of target: raise PER_SLICE_CAP, lower MIN_STARS, or relax PUSHED_AFTER."
        )


if __name__ == "__main__":
    main()
