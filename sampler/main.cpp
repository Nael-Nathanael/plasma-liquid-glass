// glassbar-sampler: paints a Panel Colorizer bar in the colour of the maximized
// window's title bar.
//
//   glassbar-sampler <colorizer D-Bus name> <Bar preset directory>
//
// The KWin script in kwin-script/ calls sample("x y width") with the frame of the
// active window whenever that window is maximized. This reads a thin strip of
// pixels across the top of it, takes the most common colour (so the title text and
// the buttons do not count), writes it into the preset, and has Panel Colorizer
// load the preset again.
//
// KWin only lets a process take screenshots if a .desktop file for its executable
// lists org.kde.KWin.ScreenShot2 under X-KDE-DBUS-Restricted-Interfaces. That is
// why this is a compiled program with its own .desktop file and not a script.
#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusReply>
#include <QDBusUnixFileDescriptor>
#include <QFile>
#include <QHash>
#include <QJsonDocument>
#include <QJsonObject>
#include <QTimer>

#include <unistd.h>

static const char SERVICE[] = "io.github.naelnathanael.GlassBar";

class Sampler : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "io.github.naelnathanael.GlassBar")

public:
    Sampler(const QString &colorizer, const QString &presetDir)
        : m_colorizer(colorizer)
        , m_presetDir(presetDir)
    {
        // The window is still moving when KWin reports it. Look once the maximize
        // animation is over, and once more for apps that paint late.
        m_first.setSingleShot(true);
        m_first.setInterval(350);
        m_second.setSingleShot(true);
        m_second.setInterval(1000);
        connect(&m_first, &QTimer::timeout, this, &Sampler::apply);
        connect(&m_second, &QTimer::timeout, this, &Sampler::apply);
    }

public slots:
    // One string, because KWin scripts send every number as a double.
    Q_SCRIPTABLE void sample(const QString &frame)
    {
        const QStringList f = frame.split(' ');
        if (f.size() != 3)
            return;
        m_x = f[0].toInt();
        m_y = f[1].toInt();
        m_width = f[2].toInt();
        m_first.start();
        m_second.start();
    }

private:
    void apply()
    {
        const QString bg = titleBarColor();
        if (bg.isEmpty() || bg == m_last)
            return;
        m_last = bg;

        const int r = bg.mid(1, 2).toInt(nullptr, 16), g = bg.mid(3, 2).toInt(nullptr, 16), b = bg.mid(5, 2).toInt(nullptr, 16);
        const QString fg = 0.299 * r + 0.587 * g + 0.114 * b > 140 ? "#1b1b1b" : "#ffffff";

        // The colours go into the preset on disk, not over D-Bus one by one: Panel
        // Colorizer's listener takes one message and then re-arms, so of several
        // "property" calls in a row only the first arrives. A single "preset" call
        // does, and the file is also what it reads by itself on the next maximize.
        writePreset(bg, fg);

        // It ignores a preset path equal to the last one it loaded. These two name
        // the same directory and never match each other or the plain path.
        m_flip = !m_flip;
        QDBusInterface colorizer(m_colorizer, "/preset", m_colorizer);
        colorizer.call("preset", m_presetDir + (m_flip ? "/." : "/./."));
    }

    static QJsonObject colorObject(const QString &hex, double alpha)
    {
        return {{"enabled", true}, {"sourceType", 0}, {"custom", hex}, {"alpha", alpha}};
    }

    void writePreset(const QString &bg, const QString &fg)
    {
        QFile file(m_presetDir + "/settings.json");
        if (!file.open(QIODevice::ReadOnly))
            return;
        QJsonObject root = QJsonDocument::fromJson(file.readAll()).object();
        file.close();
        if (root.isEmpty())
            return;

        auto set = [](QJsonObject &parent, const QStringList &path, const QJsonObject &value) {
            // Rebuild the chain of objects from the leaf up: QJsonObject is a value type.
            QList<QJsonObject> chain{parent};
            for (int i = 0; i < path.size() - 1; ++i)
                chain.append(chain.last().value(path[i]).toObject());
            chain.last().insert(path.last(), value);
            for (int i = chain.size() - 1; i > 0; --i)
                chain[i - 1].insert(path[i - 1], chain[i]);
            parent = chain.first();
        };
        set(root, {"globalSettings", "panel", "normal", "backgroundColor"}, colorObject(bg, 1));
        for (const char *state : {"normal", "hovered", "expanded"})
            set(root, {"globalSettings", "widgets", state, "foregroundColor"}, colorObject(fg, 1));
        set(root, {"globalSettings", "widgets", "hovered", "backgroundColor"}, colorObject(fg, 0.12));
        set(root, {"globalSettings", "widgets", "expanded", "backgroundColor"}, colorObject(fg, 0.2));
        set(root, {"globalSettings", "trayWidgets", "normal", "foregroundColor"}, colorObject(fg, 1));

        if (file.open(QIODevice::WriteOnly | QIODevice::Truncate))
            file.write(QJsonDocument(root).toJson());
    }

    // The most common colour in a strip across the middle half of the title bar,
    // a few pixels below its top edge. Empty if KWin refuses or sends nothing.
    QString titleBarColor() const
    {
        int fds[2];
        if (pipe(fds) != 0)
            return {};
        QDBusUnixFileDescriptor writeEnd(fds[1]); // keeps its own copy
        close(fds[1]);

        QDBusInterface kwin("org.kde.KWin", "/org/kde/KWin/ScreenShot2", "org.kde.KWin.ScreenShot2");
        const QDBusReply<QVariantMap> reply =
            kwin.call("CaptureArea", m_x + m_width / 4, m_y + 4, uint(qMin(m_width / 2, 1024)), uint(1), QVariantMap(), QVariant::fromValue(writeEnd));
        writeEnd = QDBusUnixFileDescriptor();
        if (!reply.isValid()) {
            qWarning("CaptureArea: %s", qPrintable(reply.error().message()));
            close(fds[0]);
            return {};
        }

        QByteArray data;
        char chunk[16384];
        for (ssize_t n; (n = read(fds[0], chunk, sizeof chunk)) > 0;)
            data.append(chunk, n);
        close(fds[0]);

        const QVariantMap meta = reply.value();
        const int width = meta.value("width").toInt(), height = meta.value("height").toInt(), stride = meta.value("stride").toInt();
        if (width <= 0 || height <= 0 || data.size() < stride * height)
            return {};
        // QImage::Format: 16 to 18 are the RGBA8888 family, the rest KWin uses are BGRA in memory.
        const int format = meta.value("format").toInt();
        const bool rgba = format >= 16 && format <= 18;

        struct Bucket { int count = 0; long r = 0, g = 0, b = 0; };
        QHash<int, Bucket> buckets;
        for (int y = 0; y < height; ++y) {
            const auto *row = reinterpret_cast<const uchar *>(data.constData()) + y * stride;
            for (int x = 0; x < width; ++x) {
                const uchar *p = row + x * 4;
                const int r = rgba ? p[0] : p[2], g = p[1], b = rgba ? p[2] : p[0];
                Bucket &bucket = buckets[(r >> 3) << 10 | (g >> 3) << 5 | (b >> 3)];
                ++bucket.count;
                bucket.r += r;
                bucket.g += g;
                bucket.b += b;
            }
        }
        Bucket best;
        for (const Bucket &bucket : std::as_const(buckets))
            if (bucket.count > best.count)
                best = bucket;
        return QString::asprintf("#%02x%02x%02x", int(best.r / best.count), int(best.g / best.count), int(best.b / best.count));
    }

    QString m_colorizer, m_presetDir, m_last;
    bool m_flip = false;
    int m_x = 0, m_y = 0, m_width = 0;
    QTimer m_first, m_second;
};

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    if (argc != 3) {
        qWarning("usage: glassbar-sampler <colorizer D-Bus name> <Bar preset directory>");
        return 2;
    }
    Sampler sampler(argv[1], argv[2]);
    auto bus = QDBusConnection::sessionBus();
    if (!bus.registerService(SERVICE) || !bus.registerObject("/", &sampler, QDBusConnection::ExportScriptableSlots)) {
        qWarning("already running, or no session bus");
        return 1;
    }
    return app.exec();
}

#include "main.moc"
