from flask import Flask
import mysql.connector


class DBManager:
    def __init__(
        self,
        database="example",
        host="db",
        user="root",
        password_file=None,
    ):
        with open(password_file, "r") as password_handle:
            password = password_handle.read()

        self.connection = mysql.connector.connect(
            user=user,
            password=password,
            host=host,
            database=database,
            auth_plugin="mysql_native_password",
        )
        self.cursor = self.connection.cursor()

    def populate_db(self):
        self.cursor.execute(
            "CREATE TABLE IF NOT EXISTS blog "
            "(id INT AUTO_INCREMENT PRIMARY KEY, title VARCHAR(255))"
        )
        self.cursor.execute("SELECT COUNT(*) FROM blog")
        count = self.cursor.fetchone()[0]

        if count == 0:
            self.cursor.executemany(
                "INSERT INTO blog (id, title) VALUES (%s, %s)",
                [(i, "Blog post #%d" % i) for i in range(1, 5)],
            )

        self.connection.commit()

    def query_titles(self):
        self.cursor.execute("SELECT title FROM blog ORDER BY id")
        return [row[0] for row in self.cursor.fetchall()]

    def close(self):
        self.cursor.close()
        self.connection.close()


server = Flask(__name__)


@server.route("/")
def list_blog():
    conn = DBManager(password_file="/run/secrets/db-password")

    try:
        conn.populate_db()
        titles = conn.query_titles()
        return "".join(
            "<div>   Hello  " + title + "</div>"
            for title in titles
        )
    finally:
        conn.close()


if __name__ == "__main__":
    server.run(host="0.0.0.0", port=8000)
