<%@ WebHandler Language="Oxygene" Class="DeckHandler" %>

namespace;

uses
  RemObjects.Elements.RTL,
  RemObjects.Elements.RTL.Markdown,
  System.Web;

type
  DeckHandler = public class(IHttpHandler)
  public

    property IsReusable: Boolean read true;

    method ProcessRequest(aContext: HttpContext);
    begin
      var lResponse := aContext.Response;
      lResponse.AddHeader("Cache-Control", "no-store");
      var lRemote := aContext.Request.ServerVariables["REMOTE_ADDR"];
      var lHost := aContext.Request.Url:Host;
      if not (lRemote in ["127.0.0.1", "::1", "::ffff:127.0.0.1"]) or
         not (lHost in ["localhost", "127.0.0.1", "::1", "[::1]"]) then begin
        lResponse.StatusCode := 403;
        exit;
      end;

      if aContext.Request.QueryString["asset"] = "mermaid" then begin
        lResponse.ContentType := "text/javascript; charset=utf-8";
        lResponse.Write(Markdown.MermaidRuntimeJavaScript);
        exit;
      end;

      var lPath := coalesceEmpty(System.Environment.GetEnvironmentVariable("ESP_SLIDES_DECK"), aContext.Server.MapPath("~/App_Data/slides.md"));
      var lAsset := aContext.Request.QueryString["file"];
      if assigned(lAsset) then begin
        DeckAssets.Serve(lPath, lAsset, lResponse);
        exit;
      end;

      var lSource: String;
      try
        lSource := File.ReadText(lPath);
      except
        on E: System.IO.IOException do begin
          lResponse.StatusCode := 503;
          lResponse.ContentType := "text/plain; charset=utf-8";
          lResponse.Write("Could not read the deck. Check the Markdown file and save again.");
          exit;
        end;
      end;

      var lBytes := System.Text.Encoding.UTF8.GetBytes(lSource);
      var lRevision := System.Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(lBytes));
      if aContext.Request.QueryString["revision"] = "1" then begin
        lResponse.ContentType := "text/plain; charset=utf-8";
        lResponse.Write(lRevision);
        exit;
      end;

      lResponse.ContentType := "application/json; charset=utf-8";
      lResponse.Write(DeckParser.Parse(lSource, lRevision, aContext.Request.QueryString["presenter"] = "1").ToJsonString);
    end;

  end;

  DeckAssets = assembly static class
  private

    class method ContentType(aPath: not nullable String): nullable String;
    begin
      case System.IO.Path.GetExtension(aPath).ToLowerInvariant of
        ".png": exit "image/png";
        ".jpg", ".jpeg": exit "image/jpeg";
        ".gif": exit "image/gif";
        ".svg": exit "image/svg+xml";
        ".webp": exit "image/webp";
        ".avif": exit "image/avif";
        ".mp3": exit "audio/mpeg";
        ".wav": exit "audio/wav";
        ".mp4": exit "video/mp4";
        ".webm": exit "video/webm";
      end;
    end;

  public

    class method RewriteUrl(aUrl: not nullable String): nullable String;
    begin
      if aUrl.StartsWith("/") or aUrl.StartsWith("#") or aUrl.Contains(":") then
        exit;
      var lPath: System.String := aUrl;
      lPath := lPath.Split(['?', '#'], 2)[0];
      if not assigned(ContentType(System.Uri.UnescapeDataString(lPath))) then
        exit;
      exit "deck?file=" + System.Uri.EscapeDataString(lPath);
    end;

    class method Serve(aDeckPath: not nullable String; aAsset: not nullable String; aResponse: RemObjects.Elements.Web.WebResponse);
    begin
      aResponse.StatusCode := 404;
      var lRelative: System.String := System.Uri.UnescapeDataString(aAsset);
      var lType := ContentType(lRelative);
      if not assigned(lType) or lRelative.StartsWith("/") or lRelative.Contains("\") or lRelative.Contains(":") or lRelative.Contains(#0) then
        exit;

      var lPath := System.IO.Path.GetDirectoryName(System.IO.Path.GetFullPath(aDeckPath));
      var lParts := lRelative.Split('/');
      for i := 0 to length(lParts) - 1 do begin
        var lPart := lParts[i];
        if lPart = "." then
          continue;
        if (lPart = "") or (lPart = "..") then
          exit;
        lPath := System.IO.Path.Combine(lPath, lPart);
        var lEntry: System.IO.FileSystemInfo := if i = length(lParts) - 1 then new System.IO.FileInfo(lPath) else new System.IO.DirectoryInfo(lPath);
        if not lEntry.Exists or assigned(lEntry.LinkTarget) then
          exit;
      end;

      aResponse.StatusCode := 200;
      aResponse.ContentType := lType;
      aResponse.AddHeader("X-Content-Type-Options", "nosniff");
      aResponse.AddHeader("Content-Security-Policy", "sandbox; default-src 'none'");
      aResponse.TransmitFile(lPath);
    end;

  end;

  SlideReveals = assembly class
  private

    field fPrefix := "ESPReveal" + System.Guid.NewGuid.ToString("N");
    field fReplacements := new Dictionary<String, String>;
    field fOpen := new Stack<tuple of (String, String, String)>;

    method Marker(aBody: not nullable StringBuilder; aInitialHtml: not nullable String): not nullable String;
    begin
      result := fPrefix + fReplacements.Count.ToString;
      fReplacements[result] := aInitialHtml;
      // Keep the marker in its own paragraph so Markdown can parse the wrapped blocks normally.
      aBody.Append(#10).Append(result).Append(#10#10);
    end;

  public

    method Append(aBody: not nullable StringBuilder; aLine: not nullable String): Boolean;
    begin
      var lKind := "";
      var lClose := "";
      case aLine of
        "<v-click>": begin lKind := "click"; lClose := "</v-click>"; end;
        "<v-after>": begin lKind := "after"; lClose := "</v-after>"; end;
        "<v-clicks>": begin lKind := "list"; lClose := "</v-clicks>"; end;
        "<div v-click>": begin lKind := "click"; lClose := "</div>"; end;
        "<div v-after>": begin lKind := "after"; lClose := "</div>"; end;
      end;
      if length(lKind) > 0 then begin
        var lKey := Marker(aBody, "<p>"+System.Net.WebUtility.HtmlEncode(aLine)+"</p>");
        fOpen.Push((lKey, lKind, lClose));
        exit true;
      end;
      if fOpen.Count > 0 then begin
        var lOpening := fOpen.Peek;
        if aLine = lOpening[2] then begin
          fOpen.Pop;
          fReplacements[lOpening[0]] := '<div data-reveal="'+lOpening[1]+'">';
          Marker(aBody, "</div>");
          exit true;
        end;
      end;
    end;

    method Restore(aHtml: not nullable String): not nullable String;
    begin
      result := aHtml;
      for each lReplacement in fReplacements do
        result := result.Replace("<p>"+lReplacement.Key+"</p>", lReplacement.Value);
    end;

  end;

  DeckParser = assembly static class
  private

    class method FrontmatterEnd(aLines: array of System.String; aStart: Integer): Integer;
    begin
      var lHasProperty := false;
      for i := aStart to length(aLines) - 1 do begin
        var lLine: String := aLines[i];
        if lLine = "---" then
          exit if lHasProperty then i else -1;
        if (length(lLine.Trim) = 0) or lLine.TrimStart.StartsWith("#") or lLine.StartsWith(" ") then
          continue;
        if not System.Text.RegularExpressions.Regex.IsMatch(lLine, "^[A-Za-z][A-Za-z0-9_-]*[ ]*:") then
          exit -1;
        lHasProperty := true;
      end;
      exit -1;
    end;

    class method Metadata(aLines: array of System.String; aStart: Integer; aEnd: Integer; aKey: not nullable String): nullable String;
    begin
      for i := aStart to aEnd - 1 do begin
        var lLine: String := aLines[i];
        if lLine.StartsWith(aKey + ":") then
          exit lLine.Substring(length(aKey) + 1).Trim.Trim('"', '''');
      end;
      exit nil;
    end;

    class method FenceLength(aLine: not nullable String; aMarker: Char): Integer;
    begin
      result := 0;
      while (result < length(aLine)) and (aLine[result] = aMarker) do
        inc(result);
    end;

    class method ParseDuration(aValue: nullable String): nullable Integer;
    begin
      if not assigned(aValue) then
        exit;
      var lValue := (aValue as not nullable).ToLower;
      var lClock := System.Text.RegularExpressions.Regex.Match(lValue, "^([0-9]+):([0-5][0-9])$");
      var lSeconds: Int64;
      if lClock.Success then begin
        var lMinutes := Convert.TryToInt32(lClock.Groups[1].Value);
        if not assigned(lMinutes) then
          exit;
        lSeconds := Int64(lMinutes as not nullable) * 60 + Int32.Parse(lClock.Groups[2].Value);
      end
      else begin
        var lAmount := System.Text.RegularExpressions.Regex.Match(lValue, "^([0-9]+) *(s|m|min|h)?$");
        if not lAmount.Success then
          exit;
        var lNumber := Convert.TryToInt32(lAmount.Groups[1].Value);
        if not assigned(lNumber) then
          exit;
        var lUnit := lAmount.Groups[2].Value;
        var lMultiplier := if lUnit = "h" then 3600 else if lUnit in ["m", "min"] then 60 else 1;
        lSeconds := Int64(lNumber as not nullable) * lMultiplier;
      end;
      if (lSeconds > 0) and (lSeconds <= Int32.MaxValue) then
        result := Int32(lSeconds);
    end;

    class method LogoUrl(aLogo: nullable String): nullable String;
    begin
      if (length(aLogo) = 0) or (aLogo = "false") then
        exit;
      var lLogo := aLogo as not nullable;
      if lLogo.StartsWith("https://") or lLogo.StartsWith("http://") then
        exit lLogo;
      exit DeckAssets.RewriteUrl(lLogo);
    end;

    class method AddSlide(aSlides: not nullable JsonArray; aBody: not nullable StringBuilder; aLayout: not nullable String;
      aLogo: nullable String; aTheme: nullable String; aDuration: nullable Integer; aNotes: nullable String; aReveals: not nullable SlideReveals);
    begin
      var lMarkdown := aBody.ToString;
      if length(lMarkdown.Trim) = 0 then
        exit;
      var lSlide := new JsonObject;
      var lOptions := MarkdownOptions.GitHub;
      lOptions.RewriteUrl := aUrl -> DeckAssets.RewriteUrl(aUrl);
      lSlide["html"] := aReveals.Restore(Markdown.ToHtml(lMarkdown, lOptions));
      lSlide["layout"] := aLayout;
      var lLogo := LogoUrl(aLogo);
      if assigned(lLogo) then
        lSlide["logo"] := lLogo;
      if aTheme in ["light", "dark"] then
        lSlide["theme"] := aTheme as not nullable;
      if assigned(aDuration) then
        lSlide["duration"] := aDuration as not nullable;
      if length(aNotes:Trim) > 0 then
        lSlide["notes"] := Markdown.ToHtml(aNotes, lOptions);
      aSlides.Add(lSlide);
    end;
  public

    class method Parse(aSource: not nullable String; aRevision: not nullable String; aIncludeNotes: Boolean): not nullable JsonObject;
    begin
      var lNormalized: System.String := aSource.TrimStart(#$FEFF).Replace(#13#10, #10).Replace(#13, #10);
      var lLines := lNormalized.Split(#10);
      var lSlides := new JsonArray;
      var lBody := new StringBuilder;
      var lTitle := "Slides";
      var lLayout := "default";
      var lFenceWidth := 0;
      var lFenceMarker: Char := #0;
      var lInComment := false;
      var lDeckLogo: nullable String;
      var lLogo: nullable String;
      var lDeckTheme: nullable String;
      var lTheme: nullable String;
      var lDeckDuration: nullable Integer;
      var lSlideDuration: nullable Integer;
      var lNotes := new StringBuilder;
      var lReveals := new SlideReveals;
      var i := 0;

      while i < length(lLines) do begin
        var lLine: String := lLines[i];
        var lTrimmed := lLine.TrimStart;
        var lFence := (length(lTrimmed) > 0) and (length(lLine) - length(lTrimmed) <= 3)
          and (lTrimmed[0] in ['`', '~']);
        if lFence and not lInComment then begin
          var lWidth := FenceLength(lTrimmed, lTrimmed[0]);
          var lSuffix := lTrimmed.Substring(lWidth);
          if (lFenceWidth = 0) and (lWidth >= 3) and ((lTrimmed[0] <> '`') or not lSuffix.Contains("`")) then begin
            lFenceWidth := lWidth;
            lFenceMarker := lTrimmed[0];
          end
          else if (lFenceWidth > 0) and (lTrimmed[0] = lFenceMarker) and (lWidth >= lFenceWidth) and (length(lSuffix.Trim) = 0) then begin
            lFenceWidth := 0;
          end;
        end;

        if (lFenceWidth = 0) and not lInComment and (lLine.TrimEnd = "---") then begin
          AddSlide(lSlides, lBody, lLayout, lLogo, lTheme, lSlideDuration, if aIncludeNotes then lNotes.ToString else nil, lReveals);
          lBody := new StringBuilder;
          lNotes := new StringBuilder;
          lReveals := new SlideReveals;
          lLayout := "default";
          lLogo := lDeckLogo;
          lTheme := lDeckTheme;
          lSlideDuration := nil;
          var lEnd := FrontmatterEnd(lLines, i + 1);
          if lEnd >= 0 then begin
            lLogo := coalesce(Metadata(lLines, i + 1, lEnd, "logo"), lDeckLogo);
            lTheme := coalesce(Metadata(lLines, i + 1, lEnd, "theme"), lDeckTheme);
            if i = 0 then begin
              lTitle := coalesceEmpty(Metadata(lLines, i + 1, lEnd, "title"), lTitle) as not nullable;
              lDeckLogo := lLogo;
              lDeckTheme := lTheme;
              lDeckDuration := ParseDuration(Metadata(lLines, i + 1, lEnd, "duration"));
              lSlideDuration := ParseDuration(Metadata(lLines, i + 1, lEnd, "slideDuration"));
            end
            else begin
              lSlideDuration := ParseDuration(Metadata(lLines, i + 1, lEnd, "duration"));
            end;
            lLayout := coalesceEmpty(Metadata(lLines, i + 1, lEnd, "layout"), lLayout) as not nullable;
            i := lEnd;
          end;
        end
        else if lInComment then begin
          var lClose := lLine.IndexOf("-->");
          lInComment := lClose < 0;
          lNotes.Append(if lInComment then lLine else lLine.Substring(0, lClose)).Append(#10);
        end
        else if (lFenceWidth = 0) and lTrimmed.StartsWith("<!--") and
                (not lTrimmed.Contains("-->") or lTrimmed.TrimEnd.EndsWith("-->")) then begin
          lNotes := new StringBuilder;
          var lComment := lTrimmed.Substring(4);
          var lClose := lComment.IndexOf("-->");
          lInComment := lClose < 0;
          lNotes.Append((if lInComment then lComment else lComment.Substring(0, lClose)).TrimStart).Append(#10);
        end
        else begin
          if length(lTrimmed) > 0 then
            lNotes := new StringBuilder;
          if (lFenceWidth > 0) or (lLine <> lTrimmed) or not lReveals.Append(lBody, lTrimmed.TrimEnd) then
            lBody.Append(lLine).Append(#10);
        end;
        inc(i);
      end;

      AddSlide(lSlides, lBody, lLayout, lLogo, lTheme, lSlideDuration, if aIncludeNotes and not lInComment then lNotes.ToString else nil, lReveals);
      result := new JsonObject;
      result["title"] := lTitle;
      result["revision"] := aRevision;
      if assigned(lDeckDuration) then
        result["duration"] := lDeckDuration as not nullable;
      result["slides"] := lSlides;
    end;

  end;

end.
