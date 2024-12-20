import json
import os

from dotenv import load_dotenv
from flask import Flask, jsonify, request
from flask_cors import CORS
from meilisearch import Client

load_dotenv()

meili_host = os.getenv("MEILISEARCH_HOST")
meili_master_key = os.getenv("MEILISEARCH_MASTER_KEY")

if not meili_master_key:
    meili_master_key = "testkey123"
    raise Exception("Meilisearch env variables not set")

if not meili_host:
    meili_host = "http://127.0.0.1:7700"
app = Flask(__name__)
CORS(app)
client = Client(meili_host, meili_master_key)


@app.route("/health")
def health():
    return jsonify({"status": "ok"})


@app.route("/refresh_data", methods=["POST"])
def bulk_load():
    try:
        with open("data.json", "r") as f:
            data = json.load(f)

        try:
            client.delete_index("commands")
        except:
            pass

        client.create_index("commands", {"primaryKey": "id"})
        index = client.index("commands")

        index.update_filterable_attributes(["subject"])
        index.update_searchable_attributes(["description"])

        print(f"Adding documents: {data['commands']}")
        index.add_documents(data["commands"])

        return (
            jsonify({"message": "Bulk load completed", "count": len(data["commands"])}),
            200,
        )
    except Exception as e:
        print(f"Error: {str(e)}")
        return jsonify({"error": str(e)}), 500


@app.route("/refresh_synonyms", methods=["POST"])
def refresh_synonyms():
    try:
        with open("synonyms.json", "r") as f:
            synonyms = json.load(f)

        flipped = {}
        for key, values in synonyms["synonyms"].items():
            for value in values:
                if value not in flipped:
                    flipped[value] = []
                flipped[value].append(key)

        index = client.index("commands")
        index.update_settings({"synonyms": flipped})

        return jsonify({"message": "Synonyms updated"}), 200
    except Exception as e:
        print(f"Error: {str(e)}")
        return jsonify({"error": str(e)}), 500


@app.route("/<string:subject>/<string:query>", methods=["GET"])
def search(subject, query):
    """Search for single commands in command index"""
    query = query.replace("+", " ")
    print(f"Searching for: {query} in subject: {subject}")

    try:
        res = client.index("commands").search(
            query, {"filter": f"subject = '{subject}'", "limit": 1}
        )
        hits = res.get("hits", [])
        if hits:
            return hits[0]["command"], 200
        return "No command found", 404

    except Exception as e:
        print(f"Search error: {e}")
        return str(e), 500


@app.route("/guide/<string:subject>/<string:query>", methods=["GET"])
def search_guide(subject, query):
    query = query.replace("+", " ")
    try:
        res = client.index("guides").search(
            query,
            {
                "filter": f"subject = '{subject}'",
                "attributesToRetrieve": ["title", "description", "steps"],
            },
        )
        hits = res.get("hits", [])
        if hits:
            guide = hits[0]
            response = f"{guide['title']}\n\n"
            for i, step in enumerate(guide["steps"], 1):
                response += f"Step {i}: {step['description']}\n"
                response += f"$ {step['command']}\n\n"
            return response.strip(), 200
        return "No guide found", 404
    except Exception as e:
        print(f"Guide search error: {e}")
        return str(e), 500


@app.route("/all_docs", methods=["GET"])
def get_all_docs():
    try:
        index = client.index("commands")
        docs = index.get_documents({"limit": 100})
        return (
            jsonify(
                {"results": [doc for doc in docs.results], "total": len(docs.results)}
            ),
            200,
        )
    except Exception as e:
        print(f"Error: {str(e)}")
        return jsonify({"error": str(e)}), 500


@app.route("/checkhealth")
def check_health():
    """Check if the application is running and can communicate with MeiliSearch"""
    try:
        app_status = {"status": "ok"}
        meili_status = client.health().get("status", "unavailable")
        return (
            jsonify({"app_status": app_status, "meilisearch_status": meili_status}),
            200,
        )
    except Exception as e:
        print(f"Health check error: {e}")
        return (
            jsonify(
                {
                    "app_status": {"status": "error"},
                    "meilisearch_status": "unavailable",
                    "error": str(e),
                }
            ),
            500,
        )


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
