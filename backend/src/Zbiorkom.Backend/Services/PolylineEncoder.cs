using System.Text;

namespace Zbiorkom.Backend.Services;

public static class PolylineEncoder
{
    public static string Encode6(IEnumerable<(double Latitude, double Longitude)> coordinates)
    {
        const double factor = 1e6;
        var sb = new StringBuilder();
        long prevLat = 0;
        long prevLng = 0;

        foreach (var (latitude, longitude) in coordinates)
        {
            long lat = (long)Math.Round(latitude * factor);
            long lng = (long)Math.Round(longitude * factor);

            EncodeValue(lat - prevLat, sb);
            EncodeValue(lng - prevLng, sb);

            prevLat = lat;
            prevLng = lng;
        }

        return sb.ToString();
    }

    private static void EncodeValue(long value, StringBuilder sb)
    {
        long v = value < 0 ? ~(value << 1) : (value << 1);
        while (v >= 0x20)
        {
            sb.Append((char)((0x20 | (v & 0x1f)) + 63));
            v >>= 5;
        }
        sb.Append((char)(v + 63));
    }

    public static string NormalizePolish(string input)
    {
        if (string.IsNullOrWhiteSpace(input))
            return string.Empty;

        var sb = new StringBuilder(input.Length);
        foreach (var ch in input.ToLowerInvariant())
        {
            sb.Append(ch switch
            {
                'ą' => 'a',
                'ć' => 'c',
                'ę' => 'e',
                'ł' => 'l',
                'ń' => 'n',
                'ó' => 'o',
                'ś' => 's',
                'ź' or 'ż' => 'z',
                _ => ch
            });
        }
        return sb.ToString();
    }
}
