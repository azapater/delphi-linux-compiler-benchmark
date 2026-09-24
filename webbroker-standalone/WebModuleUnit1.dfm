object WebModule1: TWebModule1
  Actions = <
    item
      Default = True
      Name = 'DefaultHandler'
      PathInfo = '/'
      OnAction = WebModule1DefaultHandlerAction
    end
    item
      Name = 'ApiTest'
      PathInfo = '/api/test'
      OnAction = WebModule1ApiTestAction
    end>
  Height = 230
  Width = 415
end
